import { router } from '@inertiajs/react';
import { Check, Clock, X } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { AcertoItems } from '@/components/phamani/acerto-items';
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog';
import { defaultSelection, sumSelected } from '@/lib/acerto';
import { formatCurrency, formatDate, today } from '@/lib/format';
import { receive } from '@/routes/receivables';
import {
    confirm as confirmSettlement,
    reject as rejectSettlement,
} from '@/routes/settlements';
import { isCreditCard } from '@/types/phamani';
import type { Account, PendingSettlement, Receivable } from '@/types/phamani';

interface ReceiveModalProps {
    receivable: Receivable | null;
    accounts: Account[];
    onClose: () => void;
}

const inputClass =
    'w-full rounded-xl border-2 border-[#E8DCC4] bg-white px-3 py-2 text-[#3D2817] focus:border-[#6B4E3D] focus:outline-none';

/**
 * Quem te deve: confirmar pagamentos informados (quem usa o Phamani) e/ou registrar
 * direto o que foi pago. O valor entra na conta escolhida, sem contar como receita.
 */
export function ReceiveModal({
    receivable,
    accounts,
    onClose,
}: ReceiveModalProps) {
    const moneyAccounts = useMemo(
        () => accounts.filter((a) => !isCreditCard(a)),
        [accounts],
    );

    const [selected, setSelected] = useState<string[]>([]);
    const [accountId, setAccountId] = useState('');
    const [date, setDate] = useState(today());
    const [errors, setErrors] = useState<Record<string, string>>({});
    const [processing, setProcessing] = useState(false);

    useEffect(() => {
        if (!receivable) return;
        setSelected(defaultSelection(receivable.items));
        setAccountId((current) => current || moneyAccounts[0]?.id || '');
        setDate(today());
        setErrors({});
    }, [receivable, moneyAccounts]);

    if (!receivable) return null;

    const total = sumSelected(receivable.items, selected);
    const name = receivable.contact.name;

    function toggle(id: string) {
        setSelected((current) =>
            current.includes(id)
                ? current.filter((x) => x !== id)
                : [...current, id],
        );
    }

    function submit() {
        if (!receivable) return;

        router.post(
            receive.url(receivable.contact.id),
            { split_ids: selected, account_id: accountId, date },
            {
                preserveScroll: true,
                onStart: () => setProcessing(true),
                onFinish: () => setProcessing(false),
                onError: (e) => setErrors(e),
                onSuccess: () => onClose(),
            },
        );
    }

    return (
        <Dialog open={!!receivable} onOpenChange={(open) => !open && onClose()}>
            <DialogContent
                onOpenAutoFocus={(e) => e.preventDefault()}
                className="max-w-lg overflow-hidden border-[#E8DCC4] bg-[#F5EFE6] p-0"
            >
                <DialogHeader className="border-b border-[#E8DCC4] px-6 pt-6 pb-4">
                    <DialogTitle className="text-xl text-[#3D2817]">
                        Acerto com {name}
                    </DialogTitle>
                    <DialogDescription className="mt-1 text-sm text-[#8B7355]">
                        O que {name} te paga entra na conta escolhida, sem
                        contar como receita.
                    </DialogDescription>
                </DialogHeader>

                <div className="max-h-[60vh] space-y-5 overflow-y-auto px-6 py-4">
                    {receivable.pending.map((p) => (
                        <PendingToConfirm
                            key={p.id}
                            settlement={p}
                            name={name}
                            accounts={moneyAccounts}
                            onDone={onClose}
                        />
                    ))}

                    {receivable.items.length > 0 && (
                        <>
                            {receivable.pending.length > 0 && (
                                <p className="text-xs font-bold tracking-wide text-[#8B7355] uppercase">
                                    Ainda em aberto
                                </p>
                            )}
                            <AcertoItems
                                items={receivable.items}
                                selected={selected}
                                onToggle={toggle}
                                currentMonth={receivable.current_month}
                                currentDeadline={receivable.current_deadline}
                            />
                            {errors.split_ids && (
                                <p className="text-xs text-[#D4183D]">
                                    {errors.split_ids}
                                </p>
                            )}

                            {receivable.contact.linked && (
                                <p className="rounded-xl bg-[#FBF7F1] p-3 text-xs text-[#6B4E3D]">
                                    {name} usa o Phamani: o normal é ele(a)
                                    informar o pagamento e você só confirmar.
                                    Registre aqui se recebeu por fora.
                                </p>
                            )}

                            <div className="grid grid-cols-2 gap-3">
                                <div>
                                    <label
                                        htmlFor="receive-account"
                                        className="mb-1 ml-1 block text-xs text-[#6B4E3D]"
                                    >
                                        Caiu na conta
                                    </label>
                                    <select
                                        id="receive-account"
                                        value={accountId}
                                        onChange={(e) =>
                                            setAccountId(e.target.value)
                                        }
                                        className={inputClass}
                                    >
                                        {moneyAccounts.map((a) => (
                                            <option key={a.id} value={a.id}>
                                                {a.name}
                                            </option>
                                        ))}
                                    </select>
                                    {errors.account_id && (
                                        <p className="mt-1 text-xs text-[#D4183D]">
                                            {errors.account_id}
                                        </p>
                                    )}
                                </div>
                                <div>
                                    <label
                                        htmlFor="receive-date"
                                        className="mb-1 ml-1 block text-xs text-[#6B4E3D]"
                                    >
                                        Em
                                    </label>
                                    <input
                                        id="receive-date"
                                        type="date"
                                        value={date}
                                        onChange={(e) =>
                                            setDate(e.target.value)
                                        }
                                        className={inputClass}
                                    />
                                </div>
                            </div>
                        </>
                    )}
                </div>

                {receivable.items.length > 0 && (
                    <div className="flex items-center justify-between border-t border-[#E8DCC4] px-6 py-4">
                        <span className="text-sm text-[#6B4E3D]">
                            Total{' '}
                            <strong className="text-[#3D2817]">
                                {formatCurrency(total)}
                            </strong>
                        </span>
                        <div className="flex gap-2">
                            <button
                                type="button"
                                onClick={onClose}
                                className="rounded-xl px-4 py-2 text-sm font-semibold text-[#6B4E3D] hover:bg-[#E8DCC4]"
                            >
                                Fechar
                            </button>
                            <button
                                type="button"
                                onClick={submit}
                                disabled={
                                    processing ||
                                    selected.length === 0 ||
                                    !accountId
                                }
                                className="rounded-xl bg-[#3D2817] px-4 py-2 text-sm font-bold text-[#F5EFE6] hover:bg-[#6B4E3D] disabled:opacity-40"
                            >
                                Registrar recebimento
                            </button>
                        </div>
                    </div>
                )}
            </DialogContent>
        </Dialog>
    );
}

/** Pagamento informado por quem deve: confirmar (escolhendo a conta) ou recusar. */
function PendingToConfirm({
    settlement,
    name,
    accounts,
    onDone,
}: {
    settlement: PendingSettlement;
    name: string;
    accounts: Account[];
    onDone: () => void;
}) {
    const [accountId, setAccountId] = useState(accounts[0]?.id ?? '');
    const [error, setError] = useState<string | null>(null);

    function confirm() {
        router.post(
            confirmSettlement.url(settlement.id),
            { to_account_id: accountId },
            {
                preserveScroll: true,
                onError: (e) =>
                    setError(e.to_account_id ?? e.settlement ?? 'Erro.'),
                onSuccess: onDone,
            },
        );
    }

    function reject() {
        router.post(
            rejectSettlement.url(settlement.id),
            {},
            { preserveScroll: true, onSuccess: onDone },
        );
    }

    return (
        <div className="space-y-3 rounded-2xl border-2 border-[#6B4E3D] bg-white p-4">
            <p className="flex items-start gap-2 text-sm text-[#3D2817]">
                <Clock className="mt-0.5 h-4 w-4 shrink-0 text-[#8B7355]" />
                <span>
                    <strong>{name}</strong> informou que pagou{' '}
                    <strong>{formatCurrency(settlement.amount)}</strong> em{' '}
                    {formatDate(settlement.paid_on)} ({settlement.count}{' '}
                    {settlement.count === 1 ? 'item' : 'itens'}).
                </span>
            </p>
            <div className="flex flex-wrap items-center gap-2">
                <select
                    aria-label="Conta onde caiu"
                    value={accountId}
                    onChange={(e) => setAccountId(e.target.value)}
                    className="min-w-0 flex-1 rounded-xl border-2 border-[#E8DCC4] bg-white px-3 py-2 text-sm text-[#3D2817] focus:border-[#6B4E3D] focus:outline-none"
                >
                    {accounts.map((a) => (
                        <option key={a.id} value={a.id}>
                            Caiu em {a.name}
                        </option>
                    ))}
                </select>
                <button
                    type="button"
                    onClick={confirm}
                    disabled={!accountId}
                    className="inline-flex items-center gap-1 rounded-xl bg-[#1F5428] px-3 py-2 text-sm font-bold text-white disabled:opacity-40"
                >
                    <Check className="h-4 w-4" /> Confirmar
                </button>
                <button
                    type="button"
                    onClick={reject}
                    className="inline-flex items-center gap-1 rounded-xl px-3 py-2 text-sm font-semibold text-[#A65D57] hover:bg-[#FCE7E7]"
                >
                    <X className="h-4 w-4" /> Não recebi
                </button>
            </div>
            {error && <p className="text-xs text-[#D4183D]">{error}</p>}
        </div>
    );
}
