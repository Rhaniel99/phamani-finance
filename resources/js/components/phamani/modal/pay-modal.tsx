import { router } from '@inertiajs/react';
import { Clock } from 'lucide-react';
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
import { pay } from '@/routes/payables';
import { cancel as cancelSettlement } from '@/routes/settlements';
import { isCreditCard } from '@/types/phamani';
import type { Account, Payable } from '@/types/phamani';

interface PayModalProps {
    payable: Payable | null;
    accounts: Account[];
    onClose: () => void;
}

const inputClass =
    'w-full rounded-xl border-2 border-[#E8DCC4] bg-white px-3 py-2 text-[#3D2817] focus:border-[#6B4E3D] focus:outline-none';

/**
 * Quanto você deve a alguém: confira os itens, marque o que está pagando e informe o pagamento.
 * O valor sai da conta escolhida (não conta como despesa de novo) e fica aguardando a confirmação.
 */
export function PayModal({ payable, accounts, onClose }: PayModalProps) {
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
        if (!payable) return;
        setSelected(defaultSelection(payable.items));
        setAccountId((current) => current || moneyAccounts[0]?.id || '');
        setDate(today());
        setErrors({});
    }, [payable, moneyAccounts]);

    if (!payable) return null;

    const total = sumSelected(payable.items, selected);
    const name = payable.creditor.name;

    function toggle(id: string) {
        setSelected((current) =>
            current.includes(id)
                ? current.filter((x) => x !== id)
                : [...current, id],
        );
    }

    function submit() {
        if (!payable) return;

        router.post(
            pay.url(payable.creditor.id),
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

    function cancel(id: string) {
        router.delete(cancelSettlement.url(id), {
            preserveScroll: true,
            onSuccess: () => onClose(),
        });
    }

    return (
        <Dialog open={!!payable} onOpenChange={(open) => !open && onClose()}>
            <DialogContent
                onOpenAutoFocus={(e) => e.preventDefault()}
                className="max-w-lg overflow-hidden border-[#E8DCC4] bg-[#F5EFE6] p-0"
            >
                <DialogHeader className="border-b border-[#E8DCC4] px-6 pt-6 pb-4">
                    <DialogTitle className="text-xl text-[#3D2817]">
                        Acerto com {name}
                    </DialogTitle>
                    <DialogDescription className="mt-1 text-sm text-[#8B7355]">
                        Confira os itens e marque o que está pagando. O valor
                        sai da conta escolhida e {name} confirma quando receber.
                    </DialogDescription>
                </DialogHeader>

                <div className="max-h-[60vh] space-y-5 overflow-y-auto px-6 py-4">
                    {payable.pending.map((p) => (
                        <div
                            key={p.id}
                            className="flex items-start justify-between gap-3 rounded-2xl border border-[#E8DCC4] bg-white p-4 text-sm"
                        >
                            <span className="flex items-start gap-2 text-[#3D2817]">
                                <Clock className="mt-0.5 h-4 w-4 shrink-0 text-[#8B7355]" />
                                <span>
                                    Você pagou{' '}
                                    <strong>{formatCurrency(p.amount)}</strong>{' '}
                                    em {formatDate(p.paid_on)} · aguardando{' '}
                                    {name} confirmar.
                                </span>
                            </span>
                            <button
                                type="button"
                                onClick={() => cancel(p.id)}
                                className="shrink-0 text-xs font-semibold text-[#8B7355] underline-offset-2 hover:underline"
                            >
                                Cancelar
                            </button>
                        </div>
                    ))}

                    {payable.items.length === 0 ? (
                        <p className="rounded-2xl border border-dashed border-[#D4C5A9] p-6 text-center text-sm text-[#8B7355]">
                            Nada em aberto com {name}.
                        </p>
                    ) : (
                        <>
                            <AcertoItems
                                items={payable.items}
                                selected={selected}
                                onToggle={toggle}
                                currentMonth={payable.current_month}
                                currentDeadline={payable.current_deadline}
                            />
                            {errors.split_ids && (
                                <p className="text-xs text-[#D4183D]">
                                    {errors.split_ids}
                                </p>
                            )}

                            <div className="grid grid-cols-2 gap-3">
                                <div>
                                    <label
                                        htmlFor="pay-account"
                                        className="mb-1 ml-1 block text-xs text-[#6B4E3D]"
                                    >
                                        Saiu da conta
                                    </label>
                                    <select
                                        id="pay-account"
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
                                        htmlFor="pay-date"
                                        className="mb-1 ml-1 block text-xs text-[#6B4E3D]"
                                    >
                                        Em
                                    </label>
                                    <input
                                        id="pay-date"
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

                {payable.items.length > 0 && (
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
                                Paguei {formatCurrency(total)}
                            </button>
                        </div>
                    </div>
                )}
            </DialogContent>
        </Dialog>
    );
}
