<?php

namespace App\Services;

use App\DTOs\Import\AcceptImportData;
use App\DTOs\Import\AcceptImportLineData;
use App\DTOs\Transaction\SplitData;
use App\DTOs\Transaction\SplitParticipantData;
use App\DTOs\Transaction\StoreTransactionData;
use App\Interfaces\Services\ICreditCardService;
use App\Interfaces\Services\IStatementImportService;
use App\Interfaces\Services\IStatementOcr;
use App\Interfaces\Services\ITransactionService;
use App\Jobs\ProcessStatementImport;
use App\Models\Account;
use App\Models\CreditCardInvoice;
use App\Models\MerchantRule;
use App\Models\StatementImport;
use App\Models\Transaction;
use App\Services\Import\BradescoStatementParser;
use App\Services\Import\MerchantSuggester;
use App\Services\Import\StatementCorrector;
use App\Services\Import\StatementMatcher;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;
use RuntimeException;
use Throwable;

class StatementImportService implements IStatementImportService
{
    public function __construct(
        protected ICreditCardService $cards,
        protected ITransactionService $transactions,
        protected BradescoStatementParser $parser,
        protected StatementCorrector $corrector,
        protected StatementMatcher $matcher,
        protected MerchantSuggester $suggester,
    ) {}

    public function start(string $userId, Account $card, array $files): StatementImport
    {
        /** @var StatementImport $import */
        $import = StatementImport::query()->create([
            'user_id' => $userId,
            'account_id' => $card->id,
            'status' => 'queued',
            'stage' => 'Na fila',
        ]);

        $stored = [];
        foreach (array_values($files) as $i => $file) {
            $name = sprintf('%02d.%s', $i, strtolower($file->getClientOriginalExtension() ?: $file->extension() ?: 'bin'));
            $stored[] = (string) $file->storeAs("imports/{$import->id}", $name, 'local');
        }

        $import->update(['files' => $stored]);

        ProcessStatementImport::dispatchAfterResponse($import->id);

        return $import;
    }

    public function process(StatementImport $import): void
    {
        @set_time_limit(900);
        @ini_set('memory_limit', '512M');

        /** @var IStatementOcr $ocr */
        $ocr = app(IStatementOcr::class);

        try {
            $import->forceFill(['status' => 'processing', 'progress' => 2, 'stage' => 'Preparando o arquivo'])->save();

            $paths = array_map(fn (string $f) => Storage::disk('local')->path($f), $import->files ?? []);
            $last = 2;

            $bands = $ocr->read($paths, function (int $done, int $total) use ($import, &$last) {
                $progress = 5 + (int) floor($done / max(1, $total) * 85);
                if ($progress !== $last) {
                    $last = $progress;
                    $import->forceFill(['progress' => $progress, 'stage' => "Lendo linha {$done} de {$total}"])->save();
                }
            });

            $import->forceFill(['progress' => 92, 'stage' => 'Conferindo os totais'])->save();

            $fallback = $import->created_at?->toDateString() ?? now()->toDateString();
            $parsed = $this->parser->parse($bands, $fallback);
            $parsed = $this->corrector->fix($parsed, $ocr, $parsed['statement_date'] ?? $fallback);

            if ($parsed['lines'] === []) {
                throw new RuntimeException('Não encontrei lançamentos no arquivo. É o extrato do cartão do Bradesco (app → Cartões → Extrato)?');
            }

            $import->forceFill([
                'status' => 'ready',
                'progress' => 100,
                'stage' => null,
                'error' => null,
                'statement_date' => $parsed['statement_date'] ?? $fallback,
                'result' => $parsed,
            ])->save();
        } catch (Throwable $e) {
            report($e);

            $import->forceFill([
                'status' => 'failed',
                'stage' => null,
                'error' => $e instanceof RuntimeException ? $e->getMessage() : 'Não foi possível ler o arquivo.',
            ])->save();
        } finally {
            $ocr->cleanup();
            $this->deleteFiles($import);
        }
    }

    public function review(StatementImport $import, ?string $reference): array
    {
        /** @var Account $card */
        $card = $import->account;
        $statementDate = CarbonImmutable::parse($import->statement_date ?? $import->created_at ?? now());
        $default = $this->cards->periodFor($card, $statementDate)['reference_month'];

        $selected = $reference !== null && preg_match('/^\d{4}-\d{2}/', $reference)
            ? CarbonImmutable::parse(substr($reference, 0, 7).'-01')
            : $default;

        [$start, $closing, $due] = $this->bounds($card, $selected);

        $result = $import->result ?? ['sections' => [], 'lines' => []];
        $rules = $this->rules($import->user_id);

        // Linhas que podem ser lançadas: compras (líquidas de estorno parcial) e créditos avulsos.
        $lines = [];
        foreach ($result['lines'] as $line) {
            $section = $result['sections'][$line['section']] ?? null;
            $net = round($line['amount'] - ($line['deduction'] ?? 0), 2);
            $launchDate = $this->clamp($line['date'], $start, $closing);

            $lines[] = [
                'index' => $line['index'],
                'section' => $line['section'],
                'last4' => $section['last4'] ?? null,
                'raw' => $line['raw'],
                'description' => $line['description'],
                'date' => $line['date'],
                'date_ok' => $line['date_ok'] ?? true,
                'launch_date' => $launchDate,
                'outside_period' => $launchDate !== $line['date'],
                'amount' => $line['amount'],
                'deduction' => $line['deduction'] ?? 0,
                'net' => $net,
                'kind' => $line['kind'],
                'pair' => $line['pair'],
                'corrected' => $line['corrected'] ?? false,
                'uncertain' => $line['uncertain'] ?? false,
                'candidates' => $line['candidates'] ?? [],
                'suggestion' => $this->suggester->suggest($line['description'], $rules),
                'match' => null,
            ];
        }

        $launchable = array_values(array_filter($lines, fn (array $l) => in_array($l['kind'], ['purchase', 'refund'], true)));

        // O que já está no cartão: a fatura escolhida + compras perto das datas do extrato.
        $existing = $this->existing($card, $selected, $launchable);

        $matches = $this->matcher->match(
            array_map(fn (array $l) => [
                'index' => $l['index'],
                'date' => $l['date'],
                'amount' => $l['net'],
                'alt' => $l['deduction'] > 0 ? $l['amount'] : null,
            ], $launchable),
            array_map(fn (array $t) => [
                'id' => $t['id'],
                'date' => $t['date'],
                'amount' => $t['type'] === 'expense' ? $t['amount'] : -$t['amount'],
                'combinable' => $t['combinable'],
            ], $existing),
        );

        $matchedBy = [];
        foreach ($lines as $i => $line) {
            if (isset($matches[$line['index']])) {
                $lines[$i]['match'] = $matches[$line['index']];
                foreach ($matches[$line['index']]['ids'] as $id) {
                    $matchedBy[$id][] = $line['index'];
                }
            }
        }

        foreach ($existing as $i => $tx) {
            $existing[$i]['matched_lines'] = array_values(array_unique($matchedBy[$tx['id']] ?? []));
        }

        $invoice = CreditCardInvoice::query()
            ->where('account_id', $card->id)
            ->whereDate('reference_month', $selected->toDateString())
            ->first();

        return [
            'reference' => $selected->toDateString(),
            'references' => $this->references($card, $default),
            'period' => [
                'start' => $start->toDateString(),
                'closing' => $closing->toDateString(),
                'due' => $due->toDateString(),
            ],
            'invoice' => $invoice === null ? null : [
                'id' => $invoice->id,
                'total' => $this->cards->invoiceTotal($invoice),
                'status' => $invoice->status(),
            ],
            'sections' => array_map(fn (array $s) => [
                ...$s,
                'diff' => $s['total'] === null ? null : round((float) $s['total'] - (float) $s['sum'], 2),
            ], $result['sections']),
            'lines' => $lines,
            'existing' => $existing,
        ];
    }

    public function accept(StatementImport $import, AcceptImportData $data): int
    {
        if ($import->status !== 'ready') {
            throw ValidationException::withMessages(['import' => 'Esta importação já foi lançada ou ainda não terminou.']);
        }

        /** @var Account $card */
        $card = $import->account;
        $reference = CarbonImmutable::parse(substr($data->reference, 0, 7).'-01');
        [$start, $closing] = $this->bounds($card, $reference);

        $byIndex = collect($import->result['lines'] ?? [])->keyBy('index');

        return DB::transaction(function () use ($import, $data, $card, $start, $closing, $byIndex) {
            $created = 0;
            $seen = [];

            foreach ($data->lines as $line) {
                // A mesma linha do extrato não vira duas compras.
                if (isset($seen[$line->index]) || ! $byIndex->has($line->index)) {
                    continue;
                }
                $seen[$line->index] = true;

                /** @var Transaction $transaction */
                $transaction = $this->transactions->create($import->user_id, new StoreTransactionData(
                    description: $line->name,
                    amount: round($line->amount, 2),
                    type: $line->type,
                    category_id: $line->category_id,
                    account_id: $card->id,
                    // Lançamento atrasado (ex.: compra de setembro que só entrou agora): entra na fatura escolhida.
                    date: $this->clamp($line->date, $start, $closing),
                    split: $this->split($line),
                    tags: $line->tags,
                ));

                $transaction->forceFill(['reconciled_at' => now()])->saveQuietly();
                $created++;
            }

            if ($data->reconcile !== []) {
                Transaction::query()
                    ->where('user_id', $import->user_id)
                    ->where('account_id', $card->id)
                    ->whereIn('id', $data->reconcile)
                    ->whereNull('reconciled_at')
                    ->update(['reconciled_at' => now()]);
            }

            if ($data->remember) {
                $this->learn($import->user_id, $data->lines, $byIndex->all());
            }

            $import->forceFill([
                'status' => 'done',
                'created_count' => $created,
                'finished_at' => now(),
            ])->save();

            return $created;
        });
    }

    public function discard(StatementImport $import): void
    {
        $this->deleteFiles($import);
        $import->delete();
    }

    // -----------------------------------------------------------------------------------------

    /**
     * Início do período (dia seguinte ao fechamento anterior), fechamento e vencimento da fatura.
     *
     * @return array{CarbonImmutable, CarbonImmutable, CarbonImmutable}
     */
    private function bounds(Account $card, CarbonImmutable $reference): array
    {
        $current = $this->cards->periodForReference($card, $reference);
        $previous = $this->cards->periodForReference($card, $reference->subMonthNoOverflow());

        return [$previous['closing_date']->addDay(), $current['closing_date'], $current['due_date']];
    }

    private function clamp(string $date, CarbonImmutable $start, CarbonImmutable $closing): string
    {
        return match (true) {
            $date < $start->toDateString() => $start->toDateString(),
            $date > $closing->toDateString() => $closing->toDateString(),
            default => $date,
        };
    }

    /**
     * Três opções de fatura: a da data do extrato, a anterior e a seguinte.
     *
     * @return list<array{value: string, closing: string, due: string, total: float|null, status: string|null}>
     */
    private function references(Account $card, CarbonImmutable $default): array
    {
        $options = [];
        foreach ([-1, 0, 1] as $offset) {
            $reference = $default->addMonthsNoOverflow($offset);
            $period = $this->cards->periodForReference($card, $reference);
            $invoice = CreditCardInvoice::query()
                ->where('account_id', $card->id)
                ->whereDate('reference_month', $reference->toDateString())
                ->first();

            $options[] = [
                'value' => $reference->toDateString(),
                'closing' => $period['closing_date']->toDateString(),
                'due' => $period['due_date']->toDateString(),
                'total' => $invoice !== null ? $this->cards->invoiceTotal($invoice) : null,
                'status' => $invoice?->status(),
            ];
        }

        return $options;
    }

    /**
     * Compras do cartão na fatura escolhida e em volta das datas do extrato.
     *
     * @param  list<array{date: string}>  $lines
     * @return list<array<string, mixed>>
     */
    private function existing(Account $card, CarbonImmutable $reference, array $lines): array
    {
        $invoiceId = CreditCardInvoice::query()
            ->where('account_id', $card->id)
            ->whereDate('reference_month', $reference->toDateString())
            ->value('id');

        $dates = array_column($lines, 'date');
        $from = $dates === [] ? null : CarbonImmutable::parse(min($dates))->subDays(5)->toDateString();
        $to = $dates === [] ? null : CarbonImmutable::parse(max($dates))->addDays(5)->toDateString();

        return Transaction::query()
            ->where('user_id', $card->user_id)
            ->where('account_id', $card->id)
            ->where(function ($q) use ($invoiceId, $from, $to) {
                $q->when($invoiceId !== null, fn ($q) => $q->where('invoice_id', $invoiceId));
                if ($from !== null) {
                    $q->orWhereBetween('date', [$from, $to]);
                }
                if ($invoiceId === null && $from === null) {
                    $q->whereRaw('1 = 0');
                }
            })
            ->with([
                'category:id,name,color,icon',
                'invoice:id,reference_month',
                'installment:id,installments',
                'tags:id,name',
            ])
            ->orderByDesc('date')
            ->orderByDesc('created_at')
            ->get()
            ->map(fn (Transaction $t) => [
                'id' => $t->id,
                'name' => $t->name,
                'date' => $t->date->toDateString(),
                'type' => $t->type,
                'amount' => (float) ($t->total_amount ?? $t->amount),
                'category' => $t->category?->only(['id', 'name', 'color', 'icon']),
                'tags' => $t->tags->map->only(['id', 'name'])->values()->all(),
                'invoice_reference' => $t->invoice?->reference_month->toDateString(),
                'in_invoice' => $invoiceId !== null && $t->invoice_id === $invoiceId,
                'installment' => $t->installment_id !== null
                    ? $t->installment_number.'/'.($t->installment->installments ?? '?')
                    : null,
                'reconciled' => $t->reconciled_at !== null,
                'combinable' => $t->installment_id === null && $t->recurring_id === null,
            ])
            ->values()
            ->all();
    }

    /**
     * @return array<string, array{name: string, category_id: string|null, tags: list<string>}>
     */
    private function rules(string $userId): array
    {
        return MerchantRule::query()
            ->where('user_id', $userId)
            ->get()
            ->mapWithKeys(fn (MerchantRule $r) => [$r->key => [
                'name' => $r->name,
                'category_id' => $r->category_id,
                'tags' => array_values($r->tags ?? []),
            ]])
            ->all();
    }

    /**
     * Guarda nome/categoria/tags da loja e categoria/tags da marca (ex.: todo iFood).
     *
     * @param  array<int, AcceptImportLineData>  $lines
     * @param  array<int, array<string, mixed>>  $byIndex
     */
    private function learn(string $userId, array $lines, array $byIndex): void
    {
        foreach ($lines as $line) {
            $description = (string) ($byIndex[$line->index]['description'] ?? '');
            if ($description === '') {
                continue;
            }

            $key = $this->suggester->key($description);
            $rows = [$key => $line->name];

            $brand = $this->suggester->brand($key);
            if ($brand !== null) {
                $rows['brand:'.$brand[0]] = $brand[1];
            }

            foreach ($rows as $ruleKey => $name) {
                MerchantRule::query()->updateOrCreate(
                    ['user_id' => $userId, 'key' => $ruleKey],
                    ['name' => $name, 'category_id' => $line->category_id, 'tags' => array_values($line->tags)],
                );
            }
        }
    }

    private function split(AcceptImportLineData $line): ?SplitData
    {
        if ($line->split === null || $line->split_contact_id === null || $line->type !== 'expense') {
            return null;
        }

        return new SplitData(
            mode: 'equal',
            participants: [new SplitParticipantData(contact_id: $line->split_contact_id)],
            include_me: $line->split === 'half',
            track: true,
        );
    }

    private function deleteFiles(StatementImport $import): void
    {
        Storage::disk('local')->deleteDirectory("imports/{$import->id}");

        if ($import->exists && $import->files !== null) {
            $import->forceFill(['files' => null])->saveQuietly();
        }
    }
}
