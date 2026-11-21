import { HandCoins } from 'lucide-react';
import { useState } from 'react';
import { ContactAvatar } from '@/components/phamani/contact-avatar';
import { ReceiveModal } from '@/components/phamani/modal/receive-modal';
import { formatCurrency } from '@/lib/format';
import type { Account, Receivable } from '@/types/phamani';

interface ReceivablesCardProps {
    receivables: Receivable[];
    accounts: Account[];
}

/**
 * Compra para outra pessoa: quanto cada contato ainda te deve.
 * Clicar abre o registro do recebimento (ex.: chegou o Pix do irmão).
 */
export function ReceivablesCard({
    receivables,
    accounts,
}: ReceivablesCardProps) {
    const [selected, setSelected] = useState<Receivable | null>(null);

    if (receivables.length === 0) return null;

    return (
        <div className="space-y-4">
            <h3 className="flex items-center gap-2 font-bold text-[#3D2817]">
                <HandCoins className="h-4 w-4 text-[#6B4E3D]" />A receber
            </h3>

            <div className="space-y-3">
                {receivables.map((r) => {
                    const upcoming = r.items.length - r.due_count;
                    return (
                        <button
                            key={r.contact.id}
                            type="button"
                            onClick={() => setSelected(r)}
                            className="flex w-full items-center justify-between gap-3 rounded-2xl border border-[#E8DCC4] bg-white p-4 text-left shadow-sm transition-colors hover:bg-[#E8DCC4]/30"
                        >
                            <span className="flex min-w-0 items-center gap-3">
                                <ContactAvatar
                                    name={r.contact.name}
                                    avatar={r.contact.avatar}
                                    className="h-10 w-10 text-sm"
                                />
                                <span className="min-w-0">
                                    <span className="block truncate text-sm font-bold text-[#3D2817]">
                                        {r.contact.name}
                                    </span>
                                    <span className="block text-xs text-[#8B7355]">
                                        {r.due_count > 0
                                            ? `${r.due_count} ${r.due_count === 1 ? 'compra' : 'compras'}`
                                            : 'Nada vencido'}
                                        {upcoming > 0 &&
                                            ` · ${upcoming} ${upcoming === 1 ? 'próxima' : 'próximas'}`}
                                    </span>
                                </span>
                            </span>
                            <span className="shrink-0 text-right">
                                <span className="block text-[10px] font-bold tracking-wide text-[#8B7355] uppercase">
                                    Te deve
                                </span>
                                <span className="text-sm font-bold text-[#A65D57]">
                                    {formatCurrency(r.due_total)}
                                </span>
                            </span>
                        </button>
                    );
                })}
            </div>

            <ReceiveModal
                receivable={selected}
                accounts={accounts}
                onClose={() => setSelected(null)}
            />
        </div>
    );
}
