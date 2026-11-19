import { Link } from '@inertiajs/react';
import { CreditCard, Wallet } from 'lucide-react';
import { motion } from 'motion/react';
import { formatCurrency, formatDate } from '@/lib/format';
import { show as cardShow } from '@/routes/cards';
import { ACCOUNT_TYPE_LABELS, isCreditCard } from '@/types/phamani';
import type { Account } from '@/types/phamani';

interface AccountsListProps {
    accounts: Account[];
    onViewAll?: () => void;
    limit?: number;
}

export function AccountsList({
    accounts,
    onViewAll,
    limit = 2,
}: AccountsListProps) {
    const visible = accounts
        .filter((a) => !isCreditCard(a))
        .sort((a, b) => Number(b.balance) - Number(a.balance))
        .slice(0, limit);
    const cards = accounts.filter(isCreditCard);

    return (
        <div className="space-y-6">
            <div className="space-y-4">
                <div className="flex items-center justify-between">
                    <h3 className="font-bold text-[#3D2817]">Contas</h3>
                    {onViewAll && accounts.length > 0 && (
                        <button
                            type="button"
                            onClick={onViewAll}
                            className="text-sm text-[#6B4F3A] hover:underline"
                        >
                            Ver todas
                        </button>
                    )}
                </div>

                <div className="space-y-3">
                    {visible.map((account) => (
                        <motion.div
                            key={account.id}
                            whileHover={{ scale: 1.01 }}
                            className="flex items-center justify-between rounded-2xl bg-gradient-to-br from-[#3D2817] to-[#6B4F3A] p-4 text-[#F5EFE6] shadow-lg"
                        >
                            <div className="flex items-center gap-3">
                                <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-white/10">
                                    <Wallet className="h-5 w-5 opacity-90" />
                                </div>
                                <div>
                                    <p className="text-sm font-bold">
                                        {account.name}
                                    </p>
                                    <p className="text-xs opacity-70">
                                        {ACCOUNT_TYPE_LABELS[account.type]}
                                    </p>
                                </div>
                            </div>

                            <div className="text-right">
                                <p className="text-[10px] uppercase opacity-60">
                                    Saldo
                                </p>
                                <p className="text-sm font-bold">
                                    {formatCurrency(account.balance)}
                                </p>
                            </div>
                        </motion.div>
                    ))}
                </div>
            </div>

            {cards.length > 0 && (
                <div className="space-y-4">
                    <h3 className="font-bold text-[#3D2817]">Cartões</h3>
                    <div className="space-y-3">
                        {cards.map((card) => (
                            <CardItem key={card.id} card={card} />
                        ))}
                    </div>
                </div>
            )}
        </div>
    );
}

export function CardItem({ card }: { card: Account }) {
    const summary = card.card;
    const limit = summary?.limit ?? null;
    const usedPct =
        limit && limit > 0
            ? Math.min(100, Math.max(0, (summary!.used / limit) * 100))
            : 0;
    const invoice = summary?.current_invoice;

    return (
        <Link href={cardShow(card.id)} prefetch className="block">
            <motion.div
                whileHover={{ scale: 1.01 }}
                className="rounded-2xl border-2 border-[#3D2817] bg-[#F5EFE6] p-4 text-[#3D2817] shadow-md"
            >
                <div className="mb-3 flex items-center justify-between">
                    <div className="flex items-center gap-3">
                        <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-[#3D2817] text-[#F5EFE6]">
                            <CreditCard className="h-5 w-5" />
                        </div>
                        <div>
                            <p className="text-sm font-bold">{card.name}</p>
                            <p className="text-xs text-[#8B7355]">
                                {invoice
                                    ? `Fatura ${formatCurrency(invoice.total)} · vence ${formatDate(invoice.due_date)}`
                                    : 'Configure fechamento e vencimento'}
                            </p>
                        </div>
                    </div>
                    <div className="text-right">
                        <p className="text-[10px] text-[#8B7355] uppercase">
                            Disponível
                        </p>
                        <p className="text-sm font-bold">
                            {summary?.available != null
                                ? formatCurrency(summary.available)
                                : '—'}
                        </p>
                    </div>
                </div>

                {limit != null && limit > 0 && (
                    <div
                        className="h-2 overflow-hidden rounded-full bg-[#E8DCC4]"
                        role="progressbar"
                        aria-label="Limite usado"
                        aria-valuenow={Math.round(usedPct)}
                        aria-valuemin={0}
                        aria-valuemax={100}
                    >
                        <div
                            className={`h-full rounded-full ${usedPct > 85 ? 'bg-[#A65D57]' : 'bg-[#6B4E3D]'}`}
                            style={{ width: `${usedPct}%` }}
                        />
                    </div>
                )}
            </motion.div>
        </Link>
    );
}
