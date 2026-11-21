import { CreditCard } from 'lucide-react';
import { acertoLabel, ACERTO_GROUP_LABELS } from '@/lib/acerto';
import { formatCurrency, formatDate } from '@/lib/format';
import { cn } from '@/lib/utils';
import type { AcertoGroup, AcertoItem } from '@/types/phamani';

const GROUPS: AcertoGroup[] = ['overdue', 'current', 'upcoming'];

/**
 * Itens do acerto agrupados (em atraso / da vez / próximos), com caixinhas para escolher
 * o que está sendo pago — como conferir a planilha item por item.
 */
export function AcertoItems({
    items,
    selected,
    onToggle,
    currentMonth,
    currentDeadline,
}: {
    items: AcertoItem[];
    selected: string[];
    onToggle: (id: string) => void;
    currentMonth: string;
    currentDeadline: string;
}) {
    return (
        <div className="space-y-4">
            {GROUPS.map((group) => {
                const groupItems = items.filter((i) => i.group === group);
                if (groupItems.length === 0) return null;

                const title =
                    group === 'current'
                        ? acertoLabel(currentMonth, currentDeadline)
                        : ACERTO_GROUP_LABELS[group];
                const total = groupItems.reduce((s, i) => s + i.amount, 0);

                return (
                    <div key={group}>
                        <p
                            className={cn(
                                'mb-2 flex items-center justify-between text-xs font-bold tracking-wide uppercase',
                                group === 'overdue'
                                    ? 'text-[#A65D57]'
                                    : 'text-[#8B7355]',
                            )}
                        >
                            <span>{title}</span>
                            <span>{formatCurrency(total)}</span>
                        </p>
                        <ul className="space-y-2">
                            {groupItems.map((item) => {
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
                                                onChange={() =>
                                                    onToggle(item.id)
                                                }
                                                className="h-4 w-4 accent-[#3D2817]"
                                            />
                                            <span className="min-w-0 flex-1">
                                                <span className="block truncate text-sm font-semibold text-[#3D2817]">
                                                    {item.name}
                                                </span>
                                                <span className="flex items-center gap-1 text-xs text-[#8B7355]">
                                                    {formatDate(item.date)}
                                                    {item.on_card && (
                                                        <>
                                                            {' · '}
                                                            <CreditCard className="h-3 w-3" />
                                                            fatura de{' '}
                                                            {acertoLabel(
                                                                item.month,
                                                            ).replace(
                                                                'Acerto de ',
                                                                '',
                                                            )}
                                                        </>
                                                    )}
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
            })}
        </div>
    );
}
