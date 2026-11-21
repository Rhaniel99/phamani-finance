import { Head } from '@inertiajs/react';
import { useState } from 'react';
import { DashboardContent } from '@/components/phamani/dashboard/dashboard-content';
import { DashboardHeader } from '@/components/phamani/dashboard/dashboard-header';
import { DashboardMain } from '@/components/phamani/dashboard/dashboard-main';
import { DashboardSidebar } from '@/components/phamani/dashboard/dashboard-sidebar';
import { NewTransactionModal } from '@/components/phamani/modal/new-transaction-modal';
import type {
    Account,
    CashFlowPoint,
    Category,
    CategoryPiePoint,
    DashboardPeriod,
    Kpis,
    Receivable,
    Transaction,
} from '@/types/phamani';

interface DashboardProps {
    period: DashboardPeriod;
    kpis: Kpis;
    cashFlow: CashFlowPoint[];
    categoryPie: CategoryPiePoint[];
    recentTransactions: Transaction[];
    accounts: Account[];
    receivables: Receivable[];
    categories: Category[];
}

export default function Dashboard({
    period,
    kpis,
    cashFlow,
    categoryPie,
    recentTransactions,
    accounts,
    receivables,
    categories,
}: DashboardProps) {
    const [isNewTransactionOpen, setIsNewTransactionOpen] = useState(false);

    return (
        <>
            <Head title="Dashboard" />

            <div className="p-6 md:p-8">
                <DashboardHeader
                    title="Phamani"
                    subtitle="Gestão Financeira Pessoal"
                />

                <DashboardMain
                    left={
                        <DashboardContent
                            kpis={kpis}
                            period={period}
                            cashFlow={cashFlow}
                            categoryPie={categoryPie}
                        />
                    }
                    right={
                        <DashboardSidebar
                            recentTransactions={recentTransactions}
                            accounts={accounts}
                            receivables={receivables}
                            onNewTransaction={() =>
                                setIsNewTransactionOpen(true)
                            }
                        />
                    }
                />

                <NewTransactionModal
                    isOpen={isNewTransactionOpen}
                    onClose={() => setIsNewTransactionOpen(false)}
                    categories={categories}
                    accounts={accounts}
                />
            </div>
        </>
    );
}
