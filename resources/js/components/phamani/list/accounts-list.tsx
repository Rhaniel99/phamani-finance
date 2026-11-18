import { Wallet } from 'lucide-react';
import { motion } from 'motion/react';
import { formatCurrency } from '@/lib/format';
import { ACCOUNT_TYPE_LABELS } from '@/types/phamani';
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
    const visible = [...accounts]
        .sort((a, b) => Number(b.balance) - Number(a.balance))
        .slice(0, limit);

    return (
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
    );
}
