import { Link } from '@inertiajs/react';
import { Plus } from 'lucide-react';
import { useState } from 'react';
import { CategoryIcon } from '@/components/phamani/category-icon';
import { ReceivablesCard } from '@/components/phamani/dashboard/receivables-card';
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
import type {
    Account,
    Payable,
    Receivable,
    Transaction,
} from '@/types/phamani';

interface DashboardSidebarProps {
    recentTransactions: Transaction[];
    accounts: Account[];
    receivables: Receivable[];
    payables: Payable[];
    onNewTransaction: () => void;
}

export function DashboardSidebar({
    recentTransactions,
    accounts,
    receivables,
    payables,
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

            <ReceivablesCard
                receivables={receivables}
                payables={payables}
                accounts={accounts}
            />

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
