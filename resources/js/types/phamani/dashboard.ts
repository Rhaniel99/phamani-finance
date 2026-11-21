export interface KPITrend {
    value: number;
    direction: 'up' | 'down';
}

export interface KPIValue {
    value: number;
    trend: KPITrend | null;
}

export interface Kpis {
    /** Só dinheiro em contas (cartões ficam de fora). */
    total_balance: number;
    /** Faturas a pagar até a fatura atual de cada cartão. */
    open_invoices: number;
    /** Despesas vencidas e não pagas. */
    overdue: { count: number; amount: number };
    income: KPIValue;
    expense: KPIValue;
    installments: KPIValue;
}

export interface CashFlowPoint {
    label: string;
    income: number;
    expense: number;
}

export interface CategoryPiePoint {
    name: string;
    value: number;
    color: string;
}

export type DashboardPeriod = 'monthly' | 'yearly';

/** Compra para outra pessoa: o que um contato ainda te deve. */
export interface ReceivableItem {
    /** id da parte (transaction_split) */
    id: string;
    transaction_id: string;
    name: string;
    date: string;
    amount: number;
    /** A data da compra já chegou (as futuras são parcelas ainda por vir). */
    due: boolean;
}

export interface Receivable {
    contact: { id: string; name: string; avatar: string | null };
    /** Só o que já venceu. */
    due_total: number;
    due_count: number;
    items: ReceivableItem[];
}
