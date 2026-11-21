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

export type AcertoGroup = 'overdue' | 'current' | 'upcoming';

/** Uma parte no acerto do mês (o que alguém deve a quem pagou). */
export interface AcertoItem {
    /** id da parte (transaction_split) */
    id: string;
    transaction_id: string;
    name: string;
    date: string;
    amount: number;
    /** Mês do acerto (YYYY-MM): da fatura (cartão) ou da data. */
    month: string;
    /** overdue = acerto passado; current = o da vez; upcoming = meses seguintes. */
    group: AcertoGroup;
    on_card: boolean;
}

/** Pagamento informado por quem deve, aguardando confirmação. */
export interface PendingSettlement {
    id: string;
    amount: number;
    paid_on: string;
    count: number;
}

interface AcertoSummary {
    overdue_total: number;
    current_total: number;
    /** YYYY-MM do acerto da vez */
    current_month: string;
    /** 5º dia útil do acerto da vez */
    current_deadline: string;
    items: AcertoItem[];
    pending: PendingSettlement[];
}

/** Quem te deve (por contato). */
export interface Receivable extends AcertoSummary {
    contact: {
        id: string;
        name: string;
        avatar: string | null;
        linked: boolean;
    };
}

/** Quanto você deve (por pessoa que usa o Phamani). */
export interface Payable extends AcertoSummary {
    creditor: { id: string; name: string; avatar: string | null };
}
