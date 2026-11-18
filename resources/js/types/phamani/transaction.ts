import type { RecurringFrequency } from '@/types/enums';
import type { Account } from './account';
import type { Category } from './category';

export type TransactionType = 'income' | 'expense';

export interface InstallmentInfo {
    id: string;
    name: string;
    installments: number;
    installment_amount: string;
    total_amount: string;
    transactions?: Array<{
        id: string;
        installment_id: string;
        installment_number: number;
        date: string;
        amount: string;
    }>;
}

export interface Transaction {
    id: string;
    name: string;
    description: string | null;
    amount: string | number;
    type: TransactionType;
    date: string;

    category_id: string;
    category?: Pick<Category, 'id' | 'name' | 'color' | 'icon'>;

    account_id: string;
    account?: Pick<Account, 'id' | 'name' | 'type'>;

    installment_id: string | null;
    installment_number: number | null;
    installment?: InstallmentInfo | null;

    recurring_id: string | null;
    recurring?: { id: string; frequency: RecurringFrequency } | null;
}

export interface TransactionFormData {
    description: string;
    amount: number | '';
    type: TransactionType;
    category_id: string;
    account_id: string;
    date: string;

    is_installment: boolean;
    installments_count: number;
    is_recurring: boolean;
    frequency: RecurringFrequency;
}

export interface TransactionFilters {
    account_id?: string;
    category_id?: string;
    type?: TransactionType;
    month?: string;
}
