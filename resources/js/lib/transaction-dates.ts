import { formatDate } from '@/lib/format';
import type { RecurringFrequency } from '@/types/enums';

export function getNextTransactionDate(data: {
    date?: string;
    is_installment?: boolean;
    is_recurring?: boolean;
    frequency?: RecurringFrequency;
}): string | null {
    if (!data.date) return null;

    const [year, month, day] = data.date.split('-').map(Number);
    const next = new Date(year, month - 1, day);

    if (data.is_installment) {
        next.setMonth(next.getMonth() + 1);
    }

    if (data.is_recurring) {
        switch (data.frequency) {
            case 'daily':
                next.setDate(next.getDate() + 1);
                break;
            case 'weekly':
                next.setDate(next.getDate() + 7);
                break;
            case 'monthly':
                next.setMonth(next.getMonth() + 1);
                break;
            case 'yearly':
                next.setFullYear(next.getFullYear() + 1);
                break;
        }
    }

    const pad = (n: number) => String(n).padStart(2, '0');

    return formatDate(
        `${next.getFullYear()}-${pad(next.getMonth() + 1)}-${pad(next.getDate())}`,
    );
}
