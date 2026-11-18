import type { CategoryColorName } from '@/lib/category/colors';
import type { CategoryIconName } from '@/lib/category/icons';

export type EnumOption<T extends string = string> = {
    value: T;
    label: string;
};

export type ColorOption<T extends string = string> = EnumOption<T> & {
    hex: string;
};

export type RecurringFrequency = 'daily' | 'weekly' | 'monthly' | 'yearly';

export type SharedEnums = {
    recurringFrequencies: EnumOption<RecurringFrequency>[];
    categoryIcons: EnumOption<CategoryIconName>[];
    categoryColors: ColorOption<CategoryColorName>[];
};
