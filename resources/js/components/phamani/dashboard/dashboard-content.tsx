import { router } from '@inertiajs/react';
import {
    Layers,
    Loader2,
    TrendingDown,
    TrendingUp,
    Wallet,
} from 'lucide-react';
import { useState } from 'react';
import { KPICard } from '@/components/phamani/card/kpi-card';
import { Badge } from '@/components/phamani/ui/badge';
import { Card } from '@/components/phamani/ui/card';
import { CashFlowChart, CategoryPieChart } from '@/components/phamani/ui/chart';
import { formatCurrency, formatTrend } from '@/lib/format';
import type {
    CashFlowPoint,
    CategoryPiePoint,
    DashboardPeriod,
    Kpis,
} from '@/types/phamani';

interface DashboardContentProps {
    kpis: Kpis;
    period: DashboardPeriod;
    cashFlow: CashFlowPoint[];
    categoryPie: CategoryPiePoint[];
}

export function DashboardContent({
    kpis,
    period,
    cashFlow,
    categoryPie,
}: DashboardContentProps) {
    const [loading, setLoading] = useState(false);

    function changePeriod(next: DashboardPeriod) {
        if (next === period) return;

        router.reload({
            data: { period: next },
            only: ['cashFlow', 'categoryPie', 'period'],
            onStart: () => setLoading(true),
            onFinish: () => setLoading(false),
        });
    }

    const periodLabel = period === 'monthly' ? 'este mês' : 'este ano';

    return (
        <>
            <div className="grid grid-cols-1 gap-6 md:grid-cols-2 xl:grid-cols-4">
                <KPICard
                    title="Saldo Total"
                    value={formatCurrency(kpis.total_balance)}
                    icon={Wallet}
                    variant="primary"
                />
                <KPICard
                    title="Receitas do mês"
                    value={formatCurrency(kpis.income.value)}
                    trend={formatTrend(kpis.income.trend)}
                    trendUp={kpis.income.trend?.direction === 'up'}
                    icon={TrendingUp}
                />
                <KPICard
                    title="Despesas do mês"
                    value={formatCurrency(kpis.expense.value)}
                    trend={formatTrend(kpis.expense.trend)}
                    trendUp={kpis.expense.trend?.direction === 'down'}
                    icon={TrendingDown}
                />
                <KPICard
                    title="Parcelamentos"
                    value={formatCurrency(kpis.installments.value)}
                    icon={Layers}
                />
            </div>

            <div className="grid grid-cols-1 gap-6 md:grid-cols-3">
                <Card className="min-h-0 min-w-0 md:col-span-2">
                    <div className="mb-6 flex items-center justify-between">
                        <div>
                            <h3 className="font-bold text-[#3D2817]">
                                Fluxo de Caixa
                            </h3>
                            <p className="text-sm text-[#8B7355]">
                                Entradas vs Saídas {periodLabel}
                            </p>
                        </div>
                        <div className="flex gap-2">
                            <Badge
                                variant={
                                    period === 'monthly' ? 'default' : 'outline'
                                }
                                onClick={() => changePeriod('monthly')}
                            >
                                Mensal
                            </Badge>
                            <Badge
                                variant={
                                    period === 'yearly' ? 'default' : 'outline'
                                }
                                onClick={() => changePeriod('yearly')}
                            >
                                Anual
                            </Badge>
                        </div>
                    </div>

                    <div className="relative h-72 w-full overflow-hidden">
                        {loading && (
                            <div className="absolute inset-0 z-10 flex items-center justify-center bg-[#F5EFE6]/60">
                                <Loader2 className="h-6 w-6 animate-spin text-[#6B4F3A]" />
                            </div>
                        )}
                        <CashFlowChart data={cashFlow} />
                    </div>
                </Card>

                <Card className="min-w-0">
                    <div className="mb-6">
                        <h3 className="font-bold text-[#3D2817]">Categorias</h3>
                        <p className="text-sm text-[#8B7355]">
                            Despesas {periodLabel}
                        </p>
                    </div>
                    <div className="h-72 w-full">
                        <CategoryPieChart data={categoryPie} />
                    </div>
                </Card>
            </div>
        </>
    );
}
