import {
    Area,
    AreaChart,
    Cell,
    Legend,
    Pie,
    PieChart,
    ResponsiveContainer,
    Tooltip,
    XAxis,
    YAxis,
} from 'recharts';
import type { TooltipContentProps, TooltipValueType } from 'recharts';
import { formatCurrency } from '@/lib/format';
import type { CashFlowPoint, CategoryPiePoint } from '@/types/phamani';

const PALETTE = {
    success: '#4A7A5E',
    danger: '#D4183D',
    grid: '#E8DCC4',
};

const SERIES_LABELS: Record<string, string> = {
    income: 'Receitas',
    expense: 'Despesas',
};

function CustomTooltip({
    active,
    payload,
    label,
}: Partial<TooltipContentProps<TooltipValueType, string | number>>) {
    if (!active || !payload?.length) return null;

    return (
        <div className="space-y-1 rounded-xl border border-[#E8DCC4] bg-[#F5EFE6] p-3 shadow-lg">
            {label !== undefined && (
                <p className="mb-1 text-xs font-bold text-[#8B7355]">{label}</p>
            )}

            {payload.map((item) => (
                <p
                    key={String(item.dataKey ?? item.name)}
                    className="text-sm font-bold"
                    style={{ color: item.color }}
                >
                    {SERIES_LABELS[String(item.name)] ?? item.name}:{' '}
                    {formatCurrency(Number(item.value))}
                </p>
            ))}
        </div>
    );
}

export function CashFlowChart({ data }: { data: CashFlowPoint[] }) {
    if (!data.length) return null;

    return (
        <ResponsiveContainer width="100%" height={288}>
            <AreaChart
                data={data}
                margin={{ top: 10, right: 10, left: -20, bottom: 0 }}
            >
                <defs>
                    <linearGradient
                        id="incomeGradient"
                        x1="0"
                        y1="0"
                        x2="0"
                        y2="1"
                    >
                        <stop
                            offset="5%"
                            stopColor={PALETTE.success}
                            stopOpacity={0.3}
                        />
                        <stop
                            offset="95%"
                            stopColor={PALETTE.success}
                            stopOpacity={0}
                        />
                    </linearGradient>
                    <linearGradient
                        id="expenseGradient"
                        x1="0"
                        y1="0"
                        x2="0"
                        y2="1"
                    >
                        <stop
                            offset="5%"
                            stopColor={PALETTE.danger}
                            stopOpacity={0.3}
                        />
                        <stop
                            offset="95%"
                            stopColor={PALETTE.danger}
                            stopOpacity={0}
                        />
                    </linearGradient>
                </defs>

                <XAxis
                    dataKey="label"
                    axisLine={false}
                    tickLine={false}
                    tick={{ fill: '#8B7355', fontSize: 10 }}
                    dy={10}
                />
                <YAxis
                    axisLine={false}
                    tickLine={false}
                    tick={{ fill: '#8B7355', fontSize: 10 }}
                />

                <Tooltip
                    content={(props) => <CustomTooltip {...props} />}
                    cursor={{
                        stroke: PALETTE.grid,
                        strokeWidth: 1,
                        strokeDasharray: '4 4',
                    }}
                />

                <Area
                    type="monotone"
                    dataKey="income"
                    name="income"
                    stroke={PALETTE.success}
                    strokeWidth={3}
                    fill="url(#incomeGradient)"
                    animationDuration={1200}
                />
                <Area
                    type="monotone"
                    dataKey="expense"
                    name="expense"
                    stroke={PALETTE.danger}
                    strokeWidth={3}
                    fill="url(#expenseGradient)"
                    animationDuration={1200}
                />
            </AreaChart>
        </ResponsiveContainer>
    );
}

export function CategoryPieChart({ data }: { data: CategoryPiePoint[] }) {
    if (!data.length) {
        return (
            <div className="flex h-full items-center justify-center text-sm text-[#8B7355]">
                Nenhuma despesa no período
            </div>
        );
    }

    return (
        <ResponsiveContainer width="100%" height={288}>
            <PieChart>
                <Pie
                    data={data}
                    cx="50%"
                    cy="50%"
                    innerRadius={60}
                    outerRadius={80}
                    paddingAngle={5}
                    dataKey="value"
                    nameKey="name"
                    stroke="none"
                >
                    {data.map((entry) => (
                        <Cell key={entry.name} fill={entry.color} />
                    ))}
                </Pie>
                <Tooltip content={(props) => <CustomTooltip {...props} />} />
                <Legend
                    verticalAlign="bottom"
                    height={36}
                    iconType="circle"
                    formatter={(value) => (
                        <span className="ml-1 text-xs font-medium text-[#6B4F3A]">
                            {value}
                        </span>
                    )}
                />
            </PieChart>
        </ResponsiveContainer>
    );
}
