import { usePage } from '@inertiajs/react';
import type { SharedEnums } from '@/types/enums';

const EMPTY: SharedEnums = {
    recurringFrequencies: [],
    categoryIcons: [],
    categoryColors: [],
};

export function useEnums(): SharedEnums {
    return usePage().props.enums ?? EMPTY;
}
