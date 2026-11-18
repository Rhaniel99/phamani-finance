import { categoryHex } from '@/lib/category/colors';
import { categoryIcon } from '@/lib/category/icons';
import { cn } from '@/lib/utils';
import type { Category } from '@/types/phamani';

interface CategoryIconProps {
    category?: Pick<Category, 'color' | 'icon'> | null;
    className?: string;
    iconClassName?: string;
}

/** Quadrado colorido com o ícone da categoria (cor e ícone vêm por nome do backend). */
export function CategoryIcon({
    category,
    className,
    iconClassName,
}: CategoryIconProps) {
    const Icon = categoryIcon(category?.icon);

    return (
        <span
            className={cn(
                'flex items-center justify-center rounded-lg',
                className,
            )}
            style={{
                backgroundColor: category
                    ? categoryHex(category.color)
                    : '#E8DCC4',
            }}
        >
            <Icon className={cn('h-4 w-4 text-white', iconClassName)} />
        </span>
    );
}
