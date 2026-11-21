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
