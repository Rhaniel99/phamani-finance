import { router } from '@inertiajs/react';
import { useEffect, useMemo, useState } from 'react';
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog';
import { formatCurrency, formatDate, today } from '@/lib/format';
import { cn } from '@/lib/utils';
import { receive } from '@/routes/receivables';
import { isCreditCard } from '@/types/phamani';
import type { Account, Receivable } from '@/types/phamani';

interface ReceiveModalProps {
    receivable: Receivable | null;
    accounts: Account[];
    onClose: () => void;
}

const inputClass =
    'w-full rounded-xl border-2 border-[#E8DCC4] bg-white px-3 py-2 text-[#3D2817] focus:border-[#6B4E3D] focus:outline-none';

/**
 * Registrar recebimento: o contato devolveu (Pix). As compras vencidas já vêm marcadas;
 * as próximas (parcelas futuras) podem ser marcadas se ele adiantou.
 * O valor entra na conta escolhida, sem contar como receita.
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

    // Ao abrir: marca o que já venceu.
    useEffect(() => {
        if (!receivable) return;
        setSelected(receivable.items.filter((i) => i.due).map((i) => i.id));
        setAccountId((current) => current || moneyAccounts[0]?.id || '');
        setDate(today());
        setErrors({});
    }, [receivable, moneyAccounts]);

    if (!receivable) return null;

    const total = receivable.items
        .filter((i) => selected.includes(i.id))
        .reduce((sum, i) => sum + i.amount, 0);

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

    const due = receivable.items.filter((i) => i.due);
    const upcoming = receivable.items.filter((i) => !i.due);

    return (
        <Dialog open={!!receivable} onOpenChange={(open) => !open && onClose()}>
            <DialogContent
                onOpenAutoFocus={(e) => e.preventDefault()}
                className="max-w-lg overflow-hidden border-[#E8DCC4] bg-[#F5EFE6] p-0"
            >
                <DialogHeader className="border-b border-[#E8DCC4] px-6 pt-6 pb-4">
                    <DialogTitle className="text-xl text-[#3D2817]">
                        Recebimento de {receivable.contact.name}
                    </DialogTitle>
                    <DialogDescription className="mt-1 text-sm text-[#8B7355]">
                        Marque o que foi pago. O valor entra na conta escolhida,
                        sem contar como receita.
                    </DialogDescription>
                </DialogHeader>

                <div className="max-h-[55vh] space-y-4 overflow-y-auto px-6 py-4">
                    <ItemGroup
                        title="Vencidas"
                        items={due}
                        selected={selected}
                        onToggle={toggle}
                    />
                    <ItemGroup
                        title="Próximas (se ele adiantou)"
                        items={upcoming}
                        selected={selected}
                        onToggle={toggle}
                    />
                    {errors.split_ids && (
                        <p className="text-xs text-[#D4183D]">
                            {errors.split_ids}
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
                                onChange={(e) => setAccountId(e.target.value)}
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
                                onChange={(e) => setDate(e.target.value)}
                                className={inputClass}
                            />
                        </div>
                    </div>
                </div>

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
                            Cancelar
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
                            Registrar
                        </button>
                    </div>
                </div>
            </DialogContent>
        </Dialog>
    );
}

function ItemGroup({
    title,
    items,
    selected,
    onToggle,
}: {
    title: string;
    items: Receivable['items'];
    selected: string[];
    onToggle: (id: string) => void;
}) {
    if (items.length === 0) return null;

    return (
        <div>
            <p className="mb-2 text-xs font-bold tracking-wide text-[#8B7355] uppercase">
                {title}
            </p>
            <ul className="space-y-2">
                {items.map((item) => {
                    const checked = selected.includes(item.id);
                    return (
                        <li key={item.id}>
                            <label
                                className={cn(
                                    'flex cursor-pointer items-center gap-3 rounded-xl border bg-white p-3 transition-colors',
                                    checked
                                        ? 'border-[#6B4E3D]'
                                        : 'border-[#E8DCC4] opacity-70',
                                )}
                            >
                                <input
                                    type="checkbox"
                                    checked={checked}
                                    onChange={() => onToggle(item.id)}
                                    className="h-4 w-4 accent-[#3D2817]"
                                />
                                <span className="min-w-0 flex-1">
                                    <span className="block truncate text-sm font-semibold text-[#3D2817]">
                                        {item.name}
                                    </span>
                                    <span className="text-xs text-[#8B7355]">
                                        {formatDate(item.date)}
                                    </span>
                                </span>
                                <span className="text-sm font-bold text-[#3D2817]">
                                    {formatCurrency(item.amount)}
                                </span>
                            </label>
                        </li>
                    );
                })}
            </ul>
        </div>
    );
}
