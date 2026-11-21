import {
    Banknote,
    CircleDollarSign,
    CreditCard,
    Landmark,
    PiggyBank,
    Receipt,
} from 'lucide-react';
import type { ElementType } from 'react';
import { cn } from '@/lib/utils';
import type { AccountType } from '@/types/phamani';

const ICONS: Record<AccountType, ElementType> = {
    cash: Banknote,
    checking: Landmark,
    savings: PiggyBank,
    credit: CreditCard,
    debt: Receipt,
    other: CircleDollarSign,
};

/**
 * Ícone por tipo de conta. O cartão de crédito tem fundo escuro, para não
 * confundir "Nubank" (conta) com "Nubank" (cartão).
 */
export function AccountIcon({
    type,
    className,
}: {
    type: AccountType;
    className?: string;
}) {
    const Icon = ICONS[type] ?? CircleDollarSign;
    const isCard = type === 'credit';

    return (
        <span
            className={cn(
                'flex shrink-0 items-center justify-center rounded-lg',
                isCard
                    ? 'bg-[#3D2817] text-[#F5EFE6]'
                    : 'bg-[#E8DCC4] text-[#6B4E3D]',
                className ?? 'h-8 w-8',
            )}
        >
            <Icon className="h-4 w-4" />
        </span>
    );
}
