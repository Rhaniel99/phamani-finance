import type { Category } from './category';

export type ImportStatus =
    | 'queued'
    | 'processing'
    | 'ready'
    | 'done'
    | 'failed';

/** purchase | refund (crédito avulso) | refunded (estorno que anula uma compra) | deducted (estorno parcial abatido) | balance | payment */
export type ImportLineKind =
    | 'purchase'
    | 'refund'
    | 'refunded'
    | 'deducted'
    | 'balance'
    | 'payment';

export interface StatementImportState {
    id: string;
    status: ImportStatus;
    progress: number;
    stage: string | null;
    error: string | null;
    statement_date: string | null;
    created_count: number;
}

export interface ImportSuggestion {
    key: string;
    brand: string | null;
    name: string;
    category_id: string | null;
    tags: string[];
    /** Veio de uma importação anterior (memória de lojas). */
    learned: boolean;
}

export interface ImportMatch {
    ids: string[];
    /** exact = mesmo valor e data; amount = mesmo valor; combined = soma de várias linhas */
    confidence: 'exact' | 'amount' | 'combined';
    group: number[];
}

export interface ImportLine {
    index: number;
    section: number;
    last4: string | null;
    raw: string;
    description: string;
    date: string;
    date_ok: boolean;
    launch_date: string;
    outside_period: boolean;
    amount: number;
    deduction: number;
    net: number;
    kind: ImportLineKind;
    pair: number | null;
    corrected: boolean;
    uncertain: boolean;
    candidates: number[];
    /** Parcela lida no extrato ("PARC 01/04"); null quando o banco não mostra. */
    installment: { number: number; count: number } | null;
    suggestion: ImportSuggestion;
    match: ImportMatch | null;
}

export interface ImportSection {
    label: string;
    last4: string | null;
    total: number | null;
    sum: number;
    ok: boolean;
    diff: number | null;
}

export interface ImportExisting {
    id: string;
    name: string;
    date: string;
    type: 'income' | 'expense';
    amount: number;
    category: Pick<Category, 'id' | 'name' | 'color' | 'icon'> | null;
    tags: { id: string; name: string }[];
    invoice_reference: string | null;
    in_invoice: boolean;
    installment: string | null;
    reconciled: boolean;
    matched_lines: number[];
}

export interface ImportReference {
    value: string;
    closing: string;
    due: string;
    total: number | null;
    status: 'open' | 'closed' | 'paid' | null;
}

export interface ImportReview {
    reference: string;
    references: ImportReference[];
    period: { start: string; closing: string; due: string };
    invoice: { id: string; total: number; status: string } | null;
    sections: ImportSection[];
    lines: ImportLine[];
    /** Linhas com valor que não deu para interpretar (lançar à mão). */
    unparsed: string[];
    existing: ImportExisting[];
}
