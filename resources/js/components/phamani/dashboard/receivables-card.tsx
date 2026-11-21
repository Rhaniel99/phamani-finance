import { HandCoins, Wallet } from 'lucide-react';
import { useState } from 'react';
import type { ReactNode } from 'react';
import { ContactAvatar } from '@/components/phamani/contact-avatar';
import { PayModal } from '@/components/phamani/modal/pay-modal';
import { ReceiveModal } from '@/components/phamani/modal/receive-modal';
import { acertoLabel } from '@/lib/acerto';
import { formatCurrency } from '@/lib/format';
import type { Account, Payable, Receivable } from '@/types/phamani';

interface AcertoCardsProps {
    receivables: Receivable[];
    payables: Payable[];
    accounts: Account[];
}

/**
 * Acerto do mês no dashboard:
 * - "A receber": quanto cada pessoa te deve (e pagamentos para confirmar);
 * - "A pagar": quanto você deve a quem usa o Phamani.
 */
export function ReceivablesCard({
    receivables,
    payables,
    accounts,
}: AcertoCardsProps) {
    const [receiving, setReceiving] = useState<Receivable | null>(null);
    const [paying, setPaying] = useState<Payable | null>(null);

    return (
        <>
            {payables.length > 0 && (
                <Section
                    icon={<Wallet className="h-4 w-4 text-[#6B4E3D]" />}
                    title="A pagar"
                >
                    {payables.map((p) => (
                        <AcertoRow
                            key={p.creditor.id}
                            name={p.creditor.name}
                            avatar={p.creditor.avatar}
                            summary={p}
                            label="Você deve"
                            pendingText={
                                p.pending.length > 0
                                    ? 'Pagamento informado · aguardando confirmação'
                                    : null
                            }
                            onClick={() => setPaying(p)}
                        />
                    ))}
                </Section>
            )}

            {receivables.length > 0 && (
                <Section
                    icon={<HandCoins className="h-4 w-4 text-[#6B4E3D]" />}
                    title="A receber"
                >
                    {receivables.map((r) => (
                        <AcertoRow
                            key={r.contact.id}
                            name={r.contact.name}
                            avatar={r.contact.avatar}
                            summary={r}
                            label="Te deve"
                            pendingText={
                                r.pending.length > 0
                                    ? `Pagou ${formatCurrency(r.pending.reduce((s, p) => s + p.amount, 0))} · confirmar`
                                    : null
                            }
                            onClick={() => setReceiving(r)}
                        />
                    ))}
                </Section>
            )}

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
        </>
    );
}

function Section({
    icon,
    title,
    children,
}: {
    icon: ReactNode;
    title: string;
    children: ReactNode;
}) {
    return (
        <div className="space-y-4">
            <h3 className="flex items-center gap-2 font-bold text-[#3D2817]">
                {icon}
                {title}
            </h3>
            <div className="space-y-3">{children}</div>
        </div>
    );
}

function AcertoRow({
    name,
    avatar,
    summary,
    label,
    pendingText,
    onClick,
}: {
    name: string;
    avatar: string | null;
    summary: Receivable | Payable;
    label: string;
    pendingText: string | null;
    onClick: () => void;
}) {
    const due = summary.overdue_total + summary.current_total;
    const upcoming = summary.items.filter((i) => i.group === 'upcoming').length;

    let subtitle: string;
    if (summary.overdue_total > 0) {
        subtitle = `${formatCurrency(summary.overdue_total)} em atraso`;
    } else if (summary.current_total > 0) {
        subtitle = acertoLabel(summary.current_month, summary.current_deadline);
    } else {
        subtitle = upcoming > 0 ? 'Só itens dos próximos meses' : 'Em dia';
    }

    return (
        <button
            type="button"
            onClick={onClick}
            className="flex w-full items-center justify-between gap-3 rounded-2xl border border-[#E8DCC4] bg-white p-4 text-left shadow-sm transition-colors hover:bg-[#E8DCC4]/30"
        >
            <span className="flex min-w-0 items-center gap-3">
                <ContactAvatar
                    name={name}
                    avatar={avatar}
                    className="h-10 w-10 text-sm"
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
            <span className="shrink-0 text-right">
                <span className="block text-[10px] font-bold tracking-wide text-[#8B7355] uppercase">
                    {label}
                </span>
                <span className="text-sm font-bold text-[#A65D57]">
                    {formatCurrency(due)}
                </span>
            </span>
        </button>
    );
}
