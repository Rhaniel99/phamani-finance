import { ArrowDownRight, ArrowUpRight } from 'lucide-react';
import type { ElementType } from 'react';
import { Card } from '@/components/phamani/ui/card';
import { cn } from '@/lib/utils';

interface KPICardProps {
    title: string;
    value: string;
    trend?: string;
    trendUp?: boolean;
    icon: ElementType;
    variant?: 'default' | 'primary';
}

export function KPICard({
    title,
    value,
    trend,
    trendUp,
    icon: Icon,
    variant = 'default',
}: KPICardProps) {
    const primary = variant === 'primary';

    return (
        <Card
            variant="interactive"
            className={cn(
                'relative overflow-hidden p-6',
                primary
                    ? 'border-2 border-[#3D2817] bg-[#E8DCC4]'
                    : 'bg-[#FBF7F1]',
            )}
        >
            <div className="mb-4 flex items-start justify-between">
                <div
                    className={cn(
                        'flex items-center justify-center rounded-2xl p-3',
                        primary
                            ? 'bg-[#3D2817] text-[#F5EFE6]'
                            : 'bg-[#E8DCC4] text-[#6B4F3A]',
                    )}
                >
                    <Icon className="h-6 w-6" />
                </div>

                {trend && (
                    <div
                        className={cn(
                            'flex items-center gap-1 rounded-lg px-2 py-1 text-xs font-bold',
                            trendUp
                                ? 'bg-[#E3F9E5] text-[#1F5428]'
                                : 'bg-[#FCE7E7] text-[#D4183D]',
                        )}
                    >
                        {trendUp ? (
                            <ArrowUpRight className="h-3 w-3" />
                        ) : (
                            <ArrowDownRight className="h-3 w-3" />
                        )}
                        {trend}
                    </div>
                )}
            </div>

            <p className="mb-1 text-sm font-medium text-[#8B7355]">{title}</p>
            <h3 className="text-3xl font-bold text-[#3D2817]">{value}</h3>
        </Card>
    );
}
