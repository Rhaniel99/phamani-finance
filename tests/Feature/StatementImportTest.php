<?php

namespace Tests\Feature;

use App\DTOs\Transaction\StoreTransactionData;
use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Interfaces\Services\IStatementImportService;
use App\Interfaces\Services\IStatementOcr;
use App\Interfaces\Services\ITransactionService;
use App\Jobs\ProcessStatementImport;
use App\Models\Account;
use App\Models\Category;
use App\Models\Contact;
use App\Models\MerchantRule;
use App\Models\StatementImport;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Bus;
use Illuminate\Support\Facades\Storage;
use Inertia\Testing\AssertableInertia as Assert;
use RuntimeException;
use Tests\TestCase;

/**
 * Importar o extrato do cartão: upload → OCR (falso aqui) → revisão → lançar.
 */
class StatementImportTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    private Account $card;

    private Category $food;

    protected function setUp(): void
    {
        parent::setUp();

        $this->travelTo('2026-11-23 10:00:00');
        Storage::fake('local');

        $this->user = User::factory()->create();
        app(IAccountService::class)->createDefaultForUser($this->user->id);
        app(ICategoryService::class)->createDefaultsForUser($this->user->id);

        $this->food = Category::query()
            ->where('user_id', $this->user->id)
            ->whereIn('type', ['expense', 'both'])
            ->orderBy('name')
            ->firstOrFail();

        // Fecha dia 25, vence dia 5: o extrato de 22/11 é da fatura de dezembro (26/10 a 25/11).
        $this->card = Account::create([
            'user_id' => $this->user->id,
            'name' => 'Bradesco Elo',
            'type' => 'credit',
            'balance' => 0,
            'credit_limit' => 5000,
            'closing_day' => 25,
            'due_day' => 5,
        ]);

        $bands = explode("\n", trim((string) file_get_contents(__DIR__.'/../Fixtures/bradesco-extrato.txt')));

        $this->app->bind(IStatementOcr::class, fn () => new class($bands) implements IStatementOcr
        {
            /** @param list<string> $bands */
            public function __construct(private array $bands) {}

            public function read(array $paths, callable $progress): array
            {
                $progress(count($this->bands), count($this->bands));

                return $this->bands;
            }

            public function reread(array $bands, float $scale): array
            {
                return array_combine($bands, array_map(fn (int $i) => $this->bands[$i], $bands));
            }

            public function cleanup(): void {}
        });
    }

    private function purchase(string $name, float $amount, string $date): Transaction
    {
        /** @var Transaction */
        return app(ITransactionService::class)->create($this->user->id, new StoreTransactionData(
            description: $name,
            amount: $amount,
            type: 'expense',
            category_id: $this->food->id,
            account_id: $this->card->id,
            date: $date,
        ));
    }

    private function readyImport(): StatementImport
    {
        $import = StatementImport::create([
            'user_id' => $this->user->id,
            'account_id' => $this->card->id,
            'status' => 'queued',
        ]);

        app(IStatementImportService::class)->process($import);

        return $import->refresh();
    }

    public function test_upload_stores_the_file_and_schedules_the_ocr(): void
    {
        Bus::fake();

        $this->actingAs($this->user)
            ->post(route('imports.store', $this->card), [
                'files' => [UploadedFile::fake()->create('extrato.pdf', 500, 'application/pdf')],
            ])
            ->assertRedirect();

        $import = StatementImport::query()->sole();

        $this->assertSame('queued', $import->status);
        $this->assertCount(1, $import->files ?? []);
        Storage::disk('local')->assertExists($import->files[0]);
        Bus::assertDispatchedAfterResponse(ProcessStatementImport::class);
    }

    public function test_upload_rejects_other_file_types_and_other_users_cards(): void
    {
        $this->actingAs($this->user)
            ->post(route('imports.store', $this->card), [
                'files' => [UploadedFile::fake()->create('planilha.xlsx', 10)],
            ])
            ->assertSessionHasErrors('files.0');

        $other = User::factory()->create();
        $this->actingAs($other)
            ->post(route('imports.store', $this->card), [
                'files' => [UploadedFile::fake()->create('extrato.pdf', 10, 'application/pdf')],
            ])
            ->assertNotFound();
    }

    public function test_processing_reads_the_statement_and_deletes_the_files(): void
    {
        $import = StatementImport::create([
            'user_id' => $this->user->id,
            'account_id' => $this->card->id,
            'status' => 'queued',
            'files' => ['imports/x/00.pdf'],
        ]);
        Storage::disk('local')->put('imports/'.$import->id.'/00.pdf', 'pdf');

        app(IStatementImportService::class)->process($import);
        $import->refresh();

        $this->assertSame('ready', $import->status);
        $this->assertSame(100, $import->progress);
        $this->assertSame('2026-11-22', $import->statement_date?->toDateString());
        $this->assertCount(14, $import->result['lines']);
        $this->assertNull($import->files);
        Storage::disk('local')->assertMissing('imports/'.$import->id.'/00.pdf');
    }

    public function test_ocr_failure_marks_the_import_as_failed(): void
    {
        $this->app->bind(IStatementOcr::class, fn () => new class implements IStatementOcr
        {
            public function read(array $paths, callable $progress): array
            {
                throw new RuntimeException('Arquivo ilegível.');
            }

            public function reread(array $bands, float $scale): array
            {
                return [];
            }

            public function cleanup(): void {}
        });

        $import = $this->readyImport();

        $this->assertSame('failed', $import->status);
        $this->assertSame('Arquivo ilegível.', $import->error);
    }

    public function test_review_links_lines_to_what_is_already_registered(): void
    {
        $tim = $this->purchase('Celular', 49.99, '2026-11-10');
        // "Jogos" = Epic 14,04 + Epic 39,29 + Steam 68,19 (lançados juntos).
        $games = $this->purchase('Jogos', 121.52, '2026-11-17');

        $import = $this->readyImport();

        $this->actingAs($this->user)
            ->get(route('imports.show', $import))
            ->assertInertia(fn (Assert $page) => $page
                ->component('cards/import')
                ->where('review.reference', '2026-12-01')
                ->where('review.period.start', '2026-10-26')
                ->where('review.period.closing', '2026-11-25')
                ->where('review.lines.2.match.ids', [$tim->id])
                ->where('review.lines.2.match.confidence', 'exact')
                ->where('review.lines.5.match.ids', [$games->id])
                ->where('review.lines.5.match.confidence', 'combined')
                ->where('review.lines.12.match.ids', [$games->id])
                ->where('review.lines.1.match', null)
                // Compra de setembro que só entrou agora: vai para o início do período da fatura.
                ->where('review.lines.13.launch_date', '2026-10-26')
                ->where('review.lines.13.outside_period', true)
                // Amazon 44,35 com estorno parcial de 26,90.
                ->where('review.lines.7.net', 17.45)
                ->where('review.lines.6.suggestion.name', 'iFood')
                ->where('review.lines.6.suggestion.tags', ['ifood'])
                ->has('review.existing', 2));
    }

    public function test_accept_launches_purchases_on_the_invoice_and_learns_the_merchants(): void
    {
        $tim = $this->purchase('Celular', 49.99, '2026-11-10');
        $import = $this->readyImport();

        $contact = Contact::create(['user_id' => $this->user->id, 'name' => 'Márcia']);

        $this->actingAs($this->user)
            ->post(route('imports.accept', $import), [
                'reference' => '2026-12-01',
                'remember' => true,
                'reconcile' => [$tim->id],
                'lines' => [
                    ['index' => 1, 'name' => 'Farmácia', 'amount' => 17.00, 'type' => 'expense', 'date' => '2026-11-17', 'category_id' => $this->food->id, 'tags' => []],
                    ['index' => 6, 'name' => 'iFood', 'amount' => 12.90, 'type' => 'expense', 'date' => '2026-11-15', 'category_id' => $this->food->id, 'tags' => ['ifood'],
                        'split' => 'half', 'split_contact_id' => $contact->id],
                    ['index' => 13, 'name' => 'AliExpress', 'amount' => 18.68, 'type' => 'expense', 'date' => '2026-09-16', 'category_id' => $this->food->id, 'tags' => []],
                    // A mesma linha duas vezes não vira duas compras.
                    ['index' => 13, 'name' => 'AliExpress', 'amount' => 18.68, 'type' => 'expense', 'date' => '2026-09-16', 'category_id' => $this->food->id, 'tags' => []],
                ],
            ])
            ->assertSessionHasNoErrors()
            ->assertRedirect(route('cards.show', ['account' => $this->card->id]));

        $import->refresh();
        $this->assertSame('done', $import->status);
        $this->assertSame(3, $import->created_count);

        $created = Transaction::query()
            ->where('account_id', $this->card->id)
            ->whereKeyNot($tim->id)
            ->with('invoice')
            ->get()
            ->keyBy('name');

        $this->assertCount(3, $created);
        foreach ($created as $transaction) {
            $this->assertSame('2026-12-01', $transaction->invoice?->reference_month->toDateString());
            $this->assertNotNull($transaction->reconciled_at);
        }

        // Compra antiga cai no início do período (fatura escolhida).
        $this->assertSame('2026-10-26', $created['AliExpress']->date->toDateString());

        // Dividida: valor cheio na fatura, sua parte é metade.
        $this->assertSame('12.90', $created['iFood']->total_amount);
        $this->assertSame('6.45', $created['iFood']->amount);
        $this->assertSame(['ifood'], $created['iFood']->tags()->pluck('name')->all());

        $this->assertNotNull($tim->refresh()->reconciled_at);

        $this->assertDatabaseHas('merchant_rules', ['user_id' => $this->user->id, 'key' => 'DROGARIA SOFIA', 'name' => 'Farmácia']);
        $this->assertDatabaseHas('merchant_rules', ['user_id' => $this->user->id, 'key' => 'brand:ifood', 'category_id' => $this->food->id]);

        // Não dá para lançar de novo.
        $this->actingAs($this->user)
            ->post(route('imports.accept', $import), ['reference' => '2026-12-01', 'lines' => []])
            ->assertSessionHasErrors('import');
    }

    public function test_accept_launches_an_installment_from_the_current_parcel(): void
    {
        $import = $this->readyImport();

        // Extrato mostra só a parcela (R$ 30,00); é a 2ª de 4.
        $this->actingAs($this->user)
            ->post(route('imports.accept', $import), [
                'reference' => '2026-12-01',
                'lines' => [
                    ['index' => 0, 'name' => 'Consulta', 'amount' => 30.00, 'type' => 'expense', 'date' => '2026-11-17',
                        'category_id' => $this->food->id, 'tags' => [], 'installment_number' => 2, 'installments_count' => 4],
                ],
            ])
            ->assertSessionHasNoErrors();

        $parcels = Transaction::query()->where('account_id', $this->card->id)->orderBy('installment_number')->with(['invoice', 'installment'])->get();

        $this->assertSame([2, 3, 4], $parcels->pluck('installment_number')->all());
        $this->assertSame(['30.00', '30.00', '30.00'], $parcels->pluck('amount')->all());
        $this->assertSame('Consulta (2/4)', $parcels[0]->name);
        $this->assertSame(
            ['2026-12-01', '2027-01-01', '2027-02-01'],
            $parcels->map(fn ($p) => $p->invoice?->reference_month->toDateString())->all(),
        );
        // Só a parcela desta fatura fica conferida.
        $this->assertNotNull($parcels[0]->reconciled_at);
        $this->assertNull($parcels[1]->reconciled_at);
        $this->assertEquals(120.0, (float) $parcels[0]->installment?->total_amount);
    }

    public function test_next_import_uses_the_learned_names_and_categories(): void
    {
        MerchantRule::create([
            'user_id' => $this->user->id,
            'key' => 'DROGARIA SOFIA',
            'name' => 'Farmácia',
            'category_id' => $this->food->id,
            'tags' => ['saude'],
        ]);

        $import = $this->readyImport();

        $this->actingAs($this->user)
            ->get(route('imports.show', $import))
            ->assertInertia(fn (Assert $page) => $page
                ->where('review.lines.1.suggestion.name', 'Farmácia')
                ->where('review.lines.1.suggestion.category_id', $this->food->id)
                ->where('review.lines.1.suggestion.learned', true));
    }

    public function test_other_users_cannot_see_or_accept_an_import(): void
    {
        $import = $this->readyImport();
        $other = User::factory()->create();

        $this->actingAs($other)->get(route('imports.show', $import))->assertNotFound();
        $this->actingAs($other)
            ->post(route('imports.accept', $import), ['reference' => '2026-12-01', 'lines' => []])
            ->assertNotFound();
        $this->actingAs($other)->delete(route('imports.destroy', $import))->assertNotFound();

        $this->actingAs($this->user)
            ->delete(route('imports.destroy', $import))
            ->assertRedirect(route('cards.show', ['account' => $this->card->id]));
        $this->assertModelMissing($import);
    }
}
