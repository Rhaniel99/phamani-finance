export type AccountType =
    | 'cash'
    | 'checking'
    | 'savings'
    | 'credit'
    | 'debt'
    | 'other';

export type InvoiceStatus = 'open' | 'closed' | 'paid';

export interface CardInvoiceSummary {
    id: string | null;
    /** 1º dia do mês de vencimento ("fatura de dezembro") */
    reference_month: string;
    closing_date: string;
    due_date: string;
    total: number;
    status: InvoiceStatus;
}

export interface CardSummary {
    limit: number | null;
    /** Soma das faturas não pagas (inclui parcelas futuras). */
    used: number;
    available: number | null;
    current_invoice: CardInvoiceSummary | null;
}

export interface Account {
    id: string;
    name: string;
    type: AccountType;
    /** decimal serializado pelo Laravel como string ("123.45") */
    balance: string | number;

    // Cartão de crédito
    credit_limit?: string | number | null;
    closing_day?: number | null;
    due_day?: number | null;
    payment_account_id?: string | null;
    card?: CardSummary;
}

export interface Invoice extends CardInvoiceSummary {
    id: string;
    paid_at: string | null;
    paid_amount: number | null;
    paid_from_account_id: string | null;
}

export interface CreateAccount {
    name: string;
    type: Extract<AccountType, 'cash' | 'checking' | 'savings' | 'credit'>;
    credit_limit: number | '';
    closing_day: number | '';
    due_day: number | '';
    payment_account_id: string;
}

export const ACCOUNT_TYPE_LABELS: Record<AccountType, string> = {
    cash: 'Dinheiro',
    checking: 'Conta Corrente',
    savings: 'Poupança',
    credit: 'Cartão de crédito',
    debt: 'Dívida',
    other: 'Outra',
};

export const INVOICE_STATUS_LABELS: Record<InvoiceStatus, string> = {
    open: 'Aberta',
    closed: 'Fechada',
    paid: 'Paga',
};

export const isCreditCard = (account: Pick<Account, 'type'>): boolean =>
    account.type === 'credit';
