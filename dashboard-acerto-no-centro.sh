#!/usr/bin/env bash
# Phamani — dashboard mais equilibrado
#  - "Acerto do mês" sai da lateral e vai para o corpo, abaixo dos gráficos, na largura toda:
#    A receber e A pagar lado a lado (contatos em grade), totais no topo, prazo (5º dia útil)
#    e o líquido com quem aparece nos dois lados (ex.: "com Rhaniel, no líquido, você paga R$ X").
#  - A lateral fica com Nova transação, Recentes, Contas e Cartões.
# Uso: na raiz do projeto ->  bash dashboard-acerto-no-centro.sh
set -euo pipefail
[ -f artisan ] && [ -f resources/js/pages/dashboard.tsx ] || { echo "Rode na raiz do projeto Phamani."; exit 1; }
BACKUP=".backup-$(date +%Y%m%d%H%M%S)"
backup() { if [ -f "$1" ]; then mkdir -p "$BACKUP/$(dirname "$1")"; cp "$1" "$BACKUP/$1"; fi; }
write() { backup "$1"; mkdir -p "$(dirname "$1")"; cat > "$1"; echo "  ok  $1"; }
echo "Aplicando arquivos (backup em $BACKUP/):"
backup resources/js/components/phamani/dashboard/receivables-card.tsx
rm -f resources/js/components/phamani/dashboard/receivables-card.tsx

write 'app/Services/ReimbursementService.php' <<'PHAMANI_EOF'
<?php

namespace App\Services;

use App\Interfaces\Repositories\IAccountRepository;
use App\Interfaces\Services\IReimbursementService;
use App\Models\Account;
use App\Models\Contact;
use App\Models\Settlement;
use App\Models\Transaction;
use App\Models\TransactionSplit;
use App\Models\User;
use App\Notifications\ActivityNotification;
use App\Support\Acerto;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class ReimbursementService implements IReimbursementService
{
    public function __construct(
        protected IAccountRepository $accounts,
    ) {}

    public function openForUser(string $userId): array
    {
        $current = Acerto::current();

        $open = $this->openQuery()
            ->where('transactions.user_id', $userId)
            ->whereNull('transaction_splits.settlement_id')
            ->with($this->itemRelations())
            ->get();

        $pending = Settlement::query()
            ->where('creditor_user_id', $userId)
            ->where('status', 'pending')
            ->withCount('splits')
            ->orderBy('paid_on')
            ->get();

        $contactIds = $open->pluck('contact_id')->merge($pending->pluck('contact_id'))->unique()->values();

        $contacts = Contact::query()
            ->with('linkedUser:id,avatar')
            ->whereIn('id', $contactIds)
            ->get(['id', 'name', 'linked_user_id'])
            ->keyBy('id');

        return $contactIds
            ->map(function (string $contactId) use ($open, $pending, $contacts, $current) {
                /** @var Contact $contact */
                $contact = $contacts[$contactId];

                return [
                    'contact' => [
                        'id' => $contact->id,
                        'name' => $contact->name,
                        'avatar' => $contact->linkedUser?->avatar,
                        'linked' => $contact->linked_user_id !== null,
                        // Usuário do Phamani por trás do contato (para mostrar o líquido com "A pagar").
                        'user_id' => $contact->linked_user_id,
                    ],
                    ...$this->summary($open->where('contact_id', $contactId)->values(), $current),
                    'pending' => $pending->where('contact_id', $contactId)->map(fn (Settlement $s) => $this->settlementData($s))->values()->all(),
                ];
            })
            ->sortByDesc(fn (array $r) => $r['overdue_total'] + $r['current_total'] + ($r['pending'] === [] ? 0 : 1_000_000))
            ->values()
            ->all();
    }

    public function payablesForUser(string $userId): array
    {
        $current = Acerto::current();

        $open = $this->payableQuery($userId)
            ->whereNull('transaction_splits.settlement_id')
            ->with($this->itemRelations())
            ->get();

        $pending = Settlement::query()
            ->where('debtor_user_id', $userId)
            ->where('status', 'pending')
            ->withCount('splits')
            ->orderBy('paid_on')
            ->get();

        $creditorIds = $open->pluck('transaction.user_id')->merge($pending->pluck('creditor_user_id'))->unique()->values();
        $creditors = User::query()->whereIn('id', $creditorIds)->get(['id', 'name', 'avatar'])->keyBy('id');

        return $creditorIds
            ->map(function (string $creditorId) use ($open, $pending, $creditors, $current) {
                $creditor = $creditors[$creditorId];

                return [
                    'creditor' => ['id' => $creditor->id, 'name' => $creditor->name, 'avatar' => $creditor->avatar],
                    ...$this->summary($open->where('transaction.user_id', $creditorId)->values(), $current),
                    'pending' => $pending->where('creditor_user_id', $creditorId)->map(fn (Settlement $s) => $this->settlementData($s))->values()->all(),
                ];
            })
            ->values()
            ->all();
    }

    public function receive(User $user, Contact $contact, array $splitIds, string $accountId, string $date): void
    {
        if ($contact->user_id !== $user->id) {
            abort(404);
        }

        $account = $this->moneyAccount($user, $accountId, 'account_id');

        $splits = $this->openQuery()
            ->where('transactions.user_id', $user->id)
            ->where('transaction_splits.contact_id', $contact->id)
            ->whereNull('transaction_splits.settlement_id')
            ->whereIn('transaction_splits.id', $splitIds)
            ->get();

        $this->ensureAll($splits, $splitIds);

        DB::transaction(function () use ($splits, $account, $date) {
            foreach ($splits as $split) {
                $split->forceFill([
                    'reimbursed_at' => $date,
                    'reimbursement_account_id' => $account->id,
                    'reimbursed_amount' => $split->amount,
                ])->save();
            }

            // Entra na conta, mas não é receita: é dinheiro seu voltando.
            $this->accounts->applyTransaction($account->id, (float) $splits->sum('amount'), 'income');
        });
    }

    public function pay(User $debtor, User $creditor, array $splitIds, string $fromAccountId, string $date): Settlement
    {
        $account = $this->moneyAccount($debtor, $fromAccountId, 'account_id');

        $splits = $this->payableQuery($debtor->id)
            ->where('transactions.user_id', $creditor->id)
            ->whereNull('transaction_splits.settlement_id')
            ->whereIn('transaction_splits.id', $splitIds)
            ->get();

        $this->ensureAll($splits, $splitIds);

        $amount = round((float) $splits->sum('amount'), 2);

        $settlement = DB::transaction(function () use ($debtor, $creditor, $splits, $account, $date, $amount) {
            /** @var Settlement $settlement */
            $settlement = Settlement::query()->create([
                'creditor_user_id' => $creditor->id,
                'debtor_user_id' => $debtor->id,
                'contact_id' => $splits->first()->contact_id,
                'amount' => $amount,
                'paid_on' => $date,
                'from_account_id' => $account->id,
                'status' => 'pending',
            ]);

            TransactionSplit::query()->whereIn('id', $splits->pluck('id'))->update(['settlement_id' => $settlement->id]);

            // Sai da conta de quem pagou (não é despesa: a despesa já está lançada).
            $this->accounts->applyTransaction($account->id, $amount, 'expense');

            return $settlement;
        });

        $creditor->notify(new ActivityNotification(
            'settlement',
            "{$debtor->name} pagou ".$this->money($amount),
            'Confirme o recebimento do acerto no card "A receber".',
            route('dashboard'),
        ));

        return $settlement;
    }

    public function confirm(User $creditor, Settlement $settlement, string $toAccountId): void
    {
        $this->ensureCreditor($creditor, $settlement);
        $this->ensurePending($settlement);

        $account = $this->moneyAccount($creditor, $toAccountId, 'to_account_id');

        DB::transaction(function () use ($settlement, $account) {
            foreach ($settlement->splits()->get() as $split) {
                $split->forceFill([
                    'reimbursed_at' => $settlement->paid_on->toDateString(),
                    'reimbursement_account_id' => $account->id,
                    'reimbursed_amount' => $split->amount,
                ])->save();
            }

            $this->accounts->applyTransaction($account->id, (float) $settlement->amount, 'income');

            $settlement->forceFill([
                'status' => 'confirmed',
                'to_account_id' => $account->id,
                'confirmed_at' => now(),
            ])->save();
        });

        User::query()->find($settlement->debtor_user_id)?->notify(new ActivityNotification(
            'settlement',
            "{$creditor->name} confirmou seu pagamento",
            'Acerto de '.$this->money((float) $settlement->amount).' confirmado.',
            route('dashboard'),
        ));
    }

    public function reject(User $creditor, Settlement $settlement): void
    {
        $this->ensureCreditor($creditor, $settlement);
        $this->ensurePending($settlement);

        $this->undoPayment($settlement, 'rejected');

        User::query()->find($settlement->debtor_user_id)?->notify(new ActivityNotification(
            'settlement',
            "{$creditor->name} não confirmou o pagamento",
            'O acerto de '.$this->money((float) $settlement->amount).' voltou para "a pagar" e o valor voltou para a sua conta.',
            route('dashboard'),
        ));
    }

    public function cancel(User $debtor, Settlement $settlement): void
    {
        if ($settlement->debtor_user_id !== $debtor->id) {
            abort(404);
        }
        $this->ensurePending($settlement);

        $this->undoPayment($settlement, 'rejected');
    }

    public function undo(User $user, TransactionSplit $split): void
    {
        $ownerId = Transaction::query()->whereKey($split->transaction_id)->value('user_id');

        if ($ownerId !== $user->id) {
            abort(404);
        }

        // Acerto entre usuários: desfaz a confirmação (o pagamento de quem deve continua informado).
        if ($split->settlement_id !== null) {
            $settlement = Settlement::query()->find($split->settlement_id);

            if ($settlement !== null && $settlement->status === 'confirmed') {
                DB::transaction(function () use ($settlement) {
                    foreach ($settlement->splits()->get() as $s) {
                        $this->revertBalance($s);
                        $s->forceFill(['reimbursed_at' => null, 'reimbursement_account_id' => null, 'reimbursed_amount' => null])->save();
                    }

                    $settlement->forceFill(['status' => 'pending', 'to_account_id' => null, 'confirmed_at' => null])->save();
                });
            }

            return;
        }

        if ($split->reimbursed_at === null) {
            return;
        }

        DB::transaction(function () use ($split) {
            $this->revertBalance($split);

            $split->forceFill([
                'reimbursed_at' => null,
                'reimbursement_account_id' => null,
                'reimbursed_amount' => null,
            ])->save();
        });
    }

    public function revertFor(Transaction $transaction): void
    {
        $splits = TransactionSplit::query()
            ->where('transaction_id', $transaction->id)
            ->where(fn ($q) => $q->whereNotNull('reimbursed_at')->orWhereNotNull('settlement_id'))
            ->get();

        foreach ($splits as $split) {
            // O que entrou na conta de quem recebe sai.
            $this->revertBalance($split);

            if ($split->settlement_id === null) {
                continue;
            }

            // O que saiu da conta de quem pagou volta, e o acerto diminui.
            $settlement = Settlement::query()->find($split->settlement_id);
            if ($settlement === null) {
                continue;
            }

            $amount = (float) ($split->reimbursed_amount ?? $split->amount);

            if ($settlement->from_account_id !== null) {
                $this->accounts->revertTransaction($settlement->from_account_id, $amount, 'expense');
            }

            $remaining = round((float) $settlement->amount - $amount, 2);
            $remaining > 0
                ? $settlement->forceFill(['amount' => $remaining])->save()
                : $settlement->delete();
        }
    }

    /**
     * Totais e itens de um grupo de partes em aberto.
     *
     * @param  Collection<int, TransactionSplit>  $splits
     * @return array<string, mixed>
     */
    private function summary(Collection $splits, string $current): array
    {
        $items = $splits
            ->map(function (TransactionSplit $s) use ($current) {
                $t = $s->transaction;
                $month = Acerto::monthOf($t->date, $t->invoice?->due_date);

                return [
                    'id' => $s->id,
                    'transaction_id' => $t->id,
                    'name' => $t->name,
                    'date' => $t->date->toDateString(),
                    'amount' => (float) $s->amount,
                    'month' => $month,
                    'group' => Acerto::group($month, $current),
                    'on_card' => $t->invoice_id !== null,
                ];
            })
            ->sortBy([['month', 'asc'], ['date', 'asc']])
            ->values();

        return [
            'overdue_total' => round((float) $items->where('group', 'overdue')->sum('amount'), 2),
            'current_total' => round((float) $items->where('group', 'current')->sum('amount'), 2),
            'current_month' => $current,
            'current_deadline' => Acerto::deadline($current)->toDateString(),
            'items' => $items->all(),
        ];
    }

    /** @return array<string, mixed> */
    private function settlementData(Settlement $s): array
    {
        return [
            'id' => $s->id,
            'amount' => (float) $s->amount,
            'paid_on' => $s->paid_on->toDateString(),
            'count' => (int) $s->getAttribute('splits_count'),
        ];
    }

    /** @return list<string> */
    private function itemRelations(): array
    {
        return [
            'transaction:id,user_id,name,date,invoice_id',
            'transaction.invoice:id,due_date',
        ];
    }

    private function undoPayment(Settlement $settlement, string $status): void
    {
        DB::transaction(function () use ($settlement, $status) {
            if ($settlement->from_account_id !== null) {
                $this->accounts->revertTransaction($settlement->from_account_id, (float) $settlement->amount, 'expense');
            }

            TransactionSplit::query()->where('settlement_id', $settlement->id)->update(['settlement_id' => null]);

            $settlement->forceFill(['status' => $status])->save();
        });
    }

    private function revertBalance(TransactionSplit $split): void
    {
        if ($split->reimbursement_account_id !== null && $split->reimbursed_amount !== null) {
            $this->accounts->revertTransaction($split->reimbursement_account_id, (float) $split->reimbursed_amount, 'income');
        }
    }

    private function moneyAccount(User $user, string $accountId, string $field): Account
    {
        $account = Account::query()->where('user_id', $user->id)->whereKey($accountId)->first();

        if ($account === null || $account->type === 'credit') {
            throw ValidationException::withMessages([$field => 'Escolha uma conta (cartão de crédito não serve).']);
        }

        return $account;
    }

    /**
     * @param  Collection<int, TransactionSplit>  $splits
     * @param  list<string>  $splitIds
     */
    private function ensureAll(Collection $splits, array $splitIds): void
    {
        if ($splits->isEmpty() || $splits->count() !== count(array_unique($splitIds))) {
            throw ValidationException::withMessages(['split_ids' => 'Escolha os itens do acerto que foram pagos.']);
        }
    }

    private function ensureCreditor(User $user, Settlement $settlement): void
    {
        if ($settlement->creditor_user_id !== $user->id) {
            abort(404);
        }
    }

    private function ensurePending(Settlement $settlement): void
    {
        if ($settlement->status !== 'pending') {
            throw ValidationException::withMessages(['settlement' => 'Este pagamento já foi resolvido.']);
        }
    }

    private function money(float $value): string
    {
        return 'R$ '.number_format($value, 2, ',', '.');
    }

    /**
     * Partes em aberto cobradas no acerto (despesas pagas por quem criou).
     *
     * @return Builder<TransactionSplit>
     */
    private function openQuery(): Builder
    {
        return TransactionSplit::query()
            ->select('transaction_splits.*')
            ->join('transactions', 'transactions.id', '=', 'transaction_splits.transaction_id')
            ->where('transactions.type', 'expense')
            ->whereNull('transactions.paid_by_contact_id')
            ->whereNull('transactions.mirrored_from_id')
            ->whereNotNull('transaction_splits.contact_id')
            ->where('transaction_splits.tracked', true)
            ->where('transaction_splits.amount', '>', 0)
            ->whereNull('transaction_splits.reimbursed_at')
            ->orderBy('transactions.date');
    }

    /**
     * Partes em aberto que você (usuário vinculado) deve, de divisões que você aceitou.
     *
     * @return Builder<TransactionSplit>
     */
    private function payableQuery(string $debtorId): Builder
    {
        return $this->openQuery()
            ->join('contacts', 'contacts.id', '=', 'transaction_splits.contact_id')
            ->where('contacts.linked_user_id', $debtorId)
            ->whereExists(fn ($q) => $q
                ->selectRaw('1')
                ->from('share_links')
                ->join('shares', 'shares.id', '=', 'share_links.share_id')
                ->whereColumn('share_links.source_transaction_id', 'transactions.id')
                ->where('shares.recipient_user_id', $debtorId)
                ->where('shares.status', 'accepted'));
    }
}
PHAMANI_EOF

write 'resources/js/components/phamani/dashboard/acerto-panel.tsx' <<'PHAMANI_EOF'
import { ArrowLeftRight, HandCoins, Wallet } from 'lucide-react';
import { useState } from 'react';
import type { ReactNode } from 'react';
import { ContactAvatar } from '@/components/phamani/contact-avatar';
import { PayModal } from '@/components/phamani/modal/pay-modal';
import { ReceiveModal } from '@/components/phamani/modal/receive-modal';
import { Card } from '@/components/phamani/ui/card';
import { acertoLabel } from '@/lib/acerto';
import { formatCurrency } from '@/lib/format';
import type { Account, Payable, Receivable } from '@/types/phamani';

interface AcertoPanelProps {
    receivables: Receivable[];
    payables: Payable[];
    accounts: Account[];
}

const dueOf = (s: Receivable | Payable) => s.overdue_total + s.current_total;

/**
 * Acerto do mês, no corpo do dashboard (largura toda, abaixo dos gráficos):
 * "A receber" e "A pagar" lado a lado, e o líquido com quem aparece nos dois.
 */
export function AcertoPanel({
    receivables,
    payables,
    accounts,
}: AcertoPanelProps) {
    const [receiving, setReceiving] = useState<Receivable | null>(null);
    const [paying, setPaying] = useState<Payable | null>(null);

    if (receivables.length === 0 && payables.length === 0) return null;

    const sample = payables[0] ?? receivables[0];
    const toReceive = receivables.reduce((s, r) => s + dueOf(r), 0);
    const toPay = payables.reduce((s, p) => s + dueOf(p), 0);

    // Quem te deve e a quem você deve ao mesmo tempo (ex.: o casal): mostra o líquido.
    const nets = payables
        .map((p) => {
            const r = receivables.find(
                (x) => x.contact.user_id === p.creditor.id,
            );
            return r
                ? { name: p.creditor.name, net: dueOf(r) - dueOf(p) }
                : null;
        })
        .filter((n): n is { name: string; net: number } => n !== null);

    const both = receivables.length > 0 && payables.length > 0;

    return (
        <Card className="p-6">
            <div className="mb-5 flex flex-wrap items-end justify-between gap-3">
                <div>
                    <h3 className="text-lg font-bold text-[#3D2817]">
                        Acerto do mês
                    </h3>
                    <p className="text-sm text-[#8B7355]">
                        {acertoLabel(
                            sample.current_month,
                            sample.current_deadline,
                        )}{' '}
                        (5º dia útil)
                    </p>
                </div>
                <div className="flex gap-6 text-right">
                    {receivables.length > 0 && (
                        <Total label="A receber" value={toReceive} tone="in" />
                    )}
                    {payables.length > 0 && (
                        <Total label="A pagar" value={toPay} tone="out" />
                    )}
                </div>
            </div>

            {nets.map((n) => (
                <p
                    key={n.name}
                    className="mb-5 flex items-center gap-2 rounded-xl bg-[#FBF7F1] px-4 py-3 text-sm text-[#6B4E3D]"
                >
                    <ArrowLeftRight className="h-4 w-4 shrink-0 text-[#8B7355]" />
                    <span>
                        Com <strong className="text-[#3D2817]">{n.name}</strong>
                        , no líquido,{' '}
                        {Math.abs(n.net) < 0.01 ? (
                            'vocês estão quites'
                        ) : n.net > 0 ? (
                            <>
                                você recebe{' '}
                                <strong className="text-[#1F5428]">
                                    {formatCurrency(n.net)}
                                </strong>
                            </>
                        ) : (
                            <>
                                você paga{' '}
                                <strong className="text-[#A65D57]">
                                    {formatCurrency(-n.net)}
                                </strong>
                            </>
                        )}
                        . Cada lado é pago e confirmado separadamente.
                    </span>
                </p>
            ))}

            <div
                className={
                    both
                        ? 'grid gap-6 lg:grid-cols-2'
                        : 'grid grid-cols-1 gap-6'
                }
            >
                {receivables.length > 0 && (
                    <Column
                        icon={<HandCoins className="h-4 w-4" />}
                        title="A receber"
                        wide={!both}
                    >
                        {receivables.map((r) => (
                            <AcertoRow
                                key={r.contact.id}
                                name={r.contact.name}
                                avatar={r.contact.avatar}
                                summary={r}
                                pendingText={
                                    r.pending.length > 0
                                        ? `Pagou ${formatCurrency(r.pending.reduce((s, p) => s + p.amount, 0))} · confirmar`
                                        : null
                                }
                                onClick={() => setReceiving(r)}
                            />
                        ))}
                    </Column>
                )}

                {payables.length > 0 && (
                    <Column
                        icon={<Wallet className="h-4 w-4" />}
                        title="A pagar"
                        wide={!both}
                    >
                        {payables.map((p) => (
                            <AcertoRow
                                key={p.creditor.id}
                                name={p.creditor.name}
                                avatar={p.creditor.avatar}
                                summary={p}
                                pendingText={
                                    p.pending.length > 0
                                        ? 'Pagamento informado · aguardando'
                                        : null
                                }
                                onClick={() => setPaying(p)}
                            />
                        ))}
                    </Column>
                )}
            </div>

            <ReceiveModal
                receivable={receiving}
                accounts={accounts}
                onClose={() => setReceiving(null)}
            />
            <PayModal
                payable={paying}
                accounts={accounts}
                onClose={() => setPaying(null)}
            />
        </Card>
    );
}

function Total({
    label,
    value,
    tone,
}: {
    label: string;
    value: number;
    tone: 'in' | 'out';
}) {
    return (
        <div>
            <p className="text-[10px] font-bold tracking-wide text-[#8B7355] uppercase">
                {label}
            </p>
            <p
                className={`text-xl font-bold ${tone === 'in' ? 'text-[#1F5428]' : 'text-[#A65D57]'}`}
            >
                {formatCurrency(value)}
            </p>
        </div>
    );
}

function Column({
    icon,
    title,
    wide,
    children,
}: {
    icon: ReactNode;
    title: string;
    /** Sozinho na linha: os contatos se espalham em mais colunas. */
    wide: boolean;
    children: ReactNode;
}) {
    return (
        <div>
            <h4 className="mb-3 flex items-center gap-2 text-sm font-bold text-[#6B4E3D]">
                {icon}
                {title}
            </h4>
            <div
                className={
                    wide
                        ? 'grid gap-2 sm:grid-cols-2 xl:grid-cols-3'
                        : 'grid gap-2 sm:grid-cols-2'
                }
            >
                {children}
            </div>
        </div>
    );
}

function AcertoRow({
    name,
    avatar,
    summary,
    pendingText,
    onClick,
}: {
    name: string;
    avatar: string | null;
    summary: Receivable | Payable;
    pendingText: string | null;
    onClick: () => void;
}) {
    const upcoming = summary.items.filter((i) => i.group === 'upcoming').length;

    let subtitle: string;
    if (summary.overdue_total > 0) {
        subtitle = `${formatCurrency(summary.overdue_total)} em atraso`;
    } else if (summary.current_total > 0) {
        subtitle = `${summary.items.filter((i) => i.group === 'current').length} itens`;
    } else {
        subtitle = upcoming > 0 ? 'Só próximos meses' : 'Em dia';
    }

    return (
        <button
            type="button"
            onClick={onClick}
            className="flex w-full items-center justify-between gap-3 rounded-2xl border border-[#E8DCC4] bg-white p-3 text-left transition-colors hover:bg-[#E8DCC4]/30"
        >
            <span className="flex min-w-0 items-center gap-3">
                <ContactAvatar
                    name={name}
                    avatar={avatar}
                    className="h-9 w-9 text-sm"
                />
                <span className="min-w-0">
                    <span className="block truncate text-sm font-bold text-[#3D2817]">
                        {name}
                    </span>
                    <span
                        className={
                            summary.overdue_total > 0
                                ? 'block truncate text-xs text-[#A65D57]'
                                : 'block truncate text-xs text-[#8B7355]'
                        }
                    >
                        {subtitle}
                    </span>
                    {pendingText && (
                        <span className="mt-1 inline-block rounded-md bg-[#FFF4D6] px-1.5 py-0.5 text-[10px] font-bold tracking-wide text-[#8A6100] uppercase">
                            {pendingText}
                        </span>
                    )}
                </span>
            </span>
            <span className="shrink-0 text-sm font-bold text-[#3D2817]">
                {formatCurrency(dueOf(summary))}
            </span>
        </button>
    );
}
PHAMANI_EOF

write 'resources/js/components/phamani/dashboard/dashboard-sidebar.tsx' <<'PHAMANI_EOF'
import { Link } from '@inertiajs/react';
import { Plus } from 'lucide-react';
import { useState } from 'react';
import { CategoryIcon } from '@/components/phamani/category-icon';
import { AccountsList } from '@/components/phamani/list/accounts-list';
import { CreateAccountDrawer } from '@/components/phamani/drawer/create-account-drawer';
import { AccountsListModal } from '@/components/phamani/modal/accounts-list-modal';
import { Button } from '@/components/phamani/ui/button';
import { Card } from '@/components/phamani/ui/card';
import { PaymentStatusBadge } from '@/components/phamani/payment-status-badge';
import { formatCurrency, formatDate, today } from '@/lib/format';
import { paymentStatus } from '@/lib/payment';
import { displayAmount, isFullyReimbursed, isThirdParty } from '@/lib/split';
import { index as transactionsIndex } from '@/routes/transactions';
import type { Account, Transaction } from '@/types/phamani';

interface DashboardSidebarProps {
    recentTransactions: Transaction[];
    accounts: Account[];
    onNewTransaction: () => void;
}

export function DashboardSidebar({
    recentTransactions,
    accounts,
    onNewTransaction,
}: DashboardSidebarProps) {
    const [accountsModalOpen, setAccountsModalOpen] = useState(false);
    const [editingAccount, setEditingAccount] = useState<Account | null>(null);
    const todayStr = today();

    return (
        <>
            <Button
                variant="primary"
                size="lg"
                className="flex w-full flex-col gap-2 rounded-2xl py-8 text-lg shadow-xl"
                onClick={onNewTransaction}
            >
                <Plus className="h-8 w-8" />
                Nova Transação
            </Button>

            <div className="space-y-4">
                <div className="flex items-center justify-between">
                    <h3 className="font-bold text-[#3D2817]">Recentes</h3>
                    <Link
                        href={transactionsIndex()}
                        prefetch
                        className="text-sm text-[#6B4F3A] hover:underline"
                    >
                        Ver tudo
                    </Link>
                </div>

                <div className="space-y-3">
                    {recentTransactions.length === 0 && (
                        <p className="rounded-2xl border border-dashed border-[#D4C5A9] p-4 text-center text-sm text-[#8B7355]">
                            Nenhuma transação ainda.
                        </p>
                    )}

                    {recentTransactions.map((t) => (
                        <Card
                            key={t.id}
                            variant="interactive"
                            className="flex items-center justify-between !border-0 p-4 !shadow-sm transition-colors hover:bg-[#E8DCC4]/30"
                        >
                            <div className="flex min-w-0 items-center gap-3">
                                <CategoryIcon
                                    category={t.category}
                                    className="h-10 w-10 shrink-0 rounded-xl shadow-sm"
                                    iconClassName="h-5 w-5"
                                />
                                <div className="min-w-0">
                                    <p className="truncate text-sm font-bold text-[#3D2817]">
                                        {t.name}
                                    </p>
                                    <p className="flex items-center gap-2 text-xs text-[#8B7355]">
                                        {formatDate(t.date)}
                                        {isThirdParty(t) &&
                                            !isFullyReimbursed(t) && (
                                                <span className="rounded-md bg-[#FCE7E7] px-1.5 py-0.5 text-[10px] font-bold tracking-wide text-[#A65D57] uppercase">
                                                    A receber
                                                </span>
                                            )}
                                        {t.date.slice(0, 10) > todayStr ? (
                                            <span className="rounded-md bg-[#E8DCC4] px-1.5 py-0.5 text-[10px] font-bold tracking-wide text-[#6B4E3D] uppercase">
                                                Agendada
                                            </span>
                                        ) : (
                                            paymentStatus(t) === 'overdue' && (
                                                <PaymentStatusBadge status="overdue" />
                                            )
                                        )}
                                    </p>
                                </div>
                            </div>

                            <span
                                className={`shrink-0 text-sm font-bold ${t.type === 'income' ? 'text-[#4A7A5E]' : 'text-[#3D2817]'}`}
                            >
                                {t.type === 'income' ? '+' : '-'}{' '}
                                {formatCurrency(displayAmount(t))}
                            </span>
                        </Card>
                    ))}
                </div>
            </div>

            <AccountsList
                accounts={accounts}
                onViewAll={() => setAccountsModalOpen(true)}
            />

            <AccountsListModal
                open={accountsModalOpen}
                onOpenChange={setAccountsModalOpen}
                accounts={accounts}
                onEdit={(account) => {
                    setAccountsModalOpen(false);
                    setEditingAccount(account);
                }}
            />

            <CreateAccountDrawer
                isOpen={editingAccount !== null}
                onClose={() => setEditingAccount(null)}
                accounts={accounts}
                account={editingAccount}
            />
        </>
    );
}
PHAMANI_EOF

write 'resources/js/pages/dashboard.tsx' <<'PHAMANI_EOF'
import { Head } from '@inertiajs/react';
import { useState } from 'react';
import { AcertoPanel } from '@/components/phamani/dashboard/acerto-panel';
import { DashboardContent } from '@/components/phamani/dashboard/dashboard-content';
import { DashboardHeader } from '@/components/phamani/dashboard/dashboard-header';
import { DashboardMain } from '@/components/phamani/dashboard/dashboard-main';
import { DashboardSidebar } from '@/components/phamani/dashboard/dashboard-sidebar';
import { NewTransactionModal } from '@/components/phamani/modal/new-transaction-modal';
import type {
    Account,
    CashFlowPoint,
    Category,
    CategoryPiePoint,
    DashboardPeriod,
    Kpis,
    Payable,
    Receivable,
    Transaction,
} from '@/types/phamani';

interface DashboardProps {
    period: DashboardPeriod;
    kpis: Kpis;
    cashFlow: CashFlowPoint[];
    categoryPie: CategoryPiePoint[];
    recentTransactions: Transaction[];
    accounts: Account[];
    receivables: Receivable[];
    payables: Payable[];
    categories: Category[];
}

export default function Dashboard({
    period,
    kpis,
    cashFlow,
    categoryPie,
    recentTransactions,
    accounts,
    receivables,
    payables,
    categories,
}: DashboardProps) {
    const [isNewTransactionOpen, setIsNewTransactionOpen] = useState(false);

    return (
        <>
            <Head title="Dashboard" />

            <div className="p-6 md:p-8">
                <DashboardHeader
                    title="Phamani"
                    subtitle="Gestão Financeira Pessoal"
                />

                <DashboardMain
                    left={
                        <>
                            <DashboardContent
                                kpis={kpis}
                                period={period}
                                cashFlow={cashFlow}
                                categoryPie={categoryPie}
                            />
                            {/* Acerto na largura toda: a lateral fica só com o dia a dia */}
                            <AcertoPanel
                                receivables={receivables}
                                payables={payables}
                                accounts={accounts}
                            />
                        </>
                    }
                    right={
                        <DashboardSidebar
                            recentTransactions={recentTransactions}
                            accounts={accounts}
                            onNewTransaction={() =>
                                setIsNewTransactionOpen(true)
                            }
                        />
                    }
                />

                <NewTransactionModal
                    isOpen={isNewTransactionOpen}
                    onClose={() => setIsNewTransactionOpen(false)}
                    categories={categories}
                    accounts={accounts}
                />
            </div>
        </>
    );
}
PHAMANI_EOF

write 'resources/js/types/phamani/dashboard.ts' <<'PHAMANI_EOF'
export interface KPITrend {
    value: number;
    direction: 'up' | 'down';
}

export interface KPIValue {
    value: number;
    trend: KPITrend | null;
}

export interface Kpis {
    /** Só dinheiro em contas (cartões ficam de fora). */
    total_balance: number;
    /** Faturas a pagar até a fatura atual de cada cartão. */
    open_invoices: number;
    /** Despesas vencidas e não pagas. */
    overdue: { count: number; amount: number };
    income: KPIValue;
    expense: KPIValue;
    installments: KPIValue;
}

export interface CashFlowPoint {
    label: string;
    income: number;
    expense: number;
}

export interface CategoryPiePoint {
    name: string;
    value: number;
    color: string;
}

export type DashboardPeriod = 'monthly' | 'yearly';

export type AcertoGroup = 'overdue' | 'current' | 'upcoming';

/** Uma parte no acerto do mês (o que alguém deve a quem pagou). */
export interface AcertoItem {
    /** id da parte (transaction_split) */
    id: string;
    transaction_id: string;
    name: string;
    date: string;
    amount: number;
    /** Mês do acerto (YYYY-MM): da fatura (cartão) ou da data. */
    month: string;
    /** overdue = acerto passado; current = o da vez; upcoming = meses seguintes. */
    group: AcertoGroup;
    on_card: boolean;
}

/** Pagamento informado por quem deve, aguardando confirmação. */
export interface PendingSettlement {
    id: string;
    amount: number;
    paid_on: string;
    count: number;
}

interface AcertoSummary {
    overdue_total: number;
    current_total: number;
    /** YYYY-MM do acerto da vez */
    current_month: string;
    /** 5º dia útil do acerto da vez */
    current_deadline: string;
    items: AcertoItem[];
    pending: PendingSettlement[];
}

/** Quem te deve (por contato). */
export interface Receivable extends AcertoSummary {
    contact: {
        id: string;
        name: string;
        avatar: string | null;
        linked: boolean;
        /** Usuário do Phamani por trás do contato. */
        user_id: string | null;
    };
}

/** Quanto você deve (por pessoa que usa o Phamani). */
export interface Payable extends AcertoSummary {
    creditor: { id: string; name: string; avatar: string | null };
}
PHAMANI_EOF

echo "Pronto. Commit + push."
