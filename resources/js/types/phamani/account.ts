export type AccountType =
    | 'cash'
    | 'checking'
    | 'savings'
    | 'credit'
    | 'debt'
    | 'other';

export interface Account {
    id: string;
    name: string;
    type: AccountType;
    /** decimal serializado pelo Laravel como string ("123.45") */
    balance: string | number;
}

export interface CreateAccount {
    name: string;
    type: Extract<AccountType, 'cash' | 'checking' | 'savings' | 'credit'>;
}

export const ACCOUNT_TYPE_LABELS: Record<AccountType, string> = {
    cash: 'Dinheiro',
    checking: 'Conta Corrente',
    savings: 'Poupança',
    credit: 'Crédito',
    debt: 'Dívida',
    other: 'Outra',
};
