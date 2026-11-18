import type { CategoryColorName } from '@/lib/category/colors';
import type { CategoryIconName } from '@/lib/category/icons';

export type CategoryType = 'expense' | 'income' | 'both';

export interface Category {
    id: string;
    name: string;
    color: CategoryColorName | null;
    icon: CategoryIconName | null;
    type: CategoryType;
}

export interface CreateCategory {
    name: string;
    type: CategoryType;
    color: CategoryColorName;
    icon: CategoryIconName;
}
