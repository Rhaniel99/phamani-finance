import type { RecurringFrequency } from '@/types/enums';
import type { Account } from './account';
import type { Category } from './category';
import type {
    Contact,
    MirrorSource,
    ShareLinkInfo,
    SplitForm,
    TransactionSplit,
} from './contact';
import type { Tag } from './tag';

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
    /** Débito automático */
    auto_pay?: boolean;
}

export interface Transaction {
    id: string;
    tags?: Tag[];
    name: string;
    description: string | null;
    /** Sua parte (numa divisão) ou o valor inteiro. */
    amount: string | number;
    type: TransactionType;
    date: string;

    /** Valor cheio quando a transação é dividida. */
    total_amount?: string | number | null;
    /** Quem pagou (null = você). */
    paid_by_contact_id?: string | null;
    paid_by?: Pick<Contact, 'id' | 'name' | 'linked_user_id'> | null;
    /** Pago/recebido em (null = pendente ou atrasado). */
    paid_at?: string | null;
    /** "Conferido" na lista da fatura. */
    reconciled_at?: string | null;
    splits?: TransactionSplit[];

    /** Cópia de uma divisão compartilhada por outra pessoa (somente leitura). */
    mirrored_from_id?: string | null;
    mirrored_from?: MirrorSource | null;
    /** Do lado de quem criou: status de cada pessoa com quem foi compartilhada. */
    share_links?: ShareLinkInfo[];

    category_id: string;
    category?: Pick<Category, 'id' | 'name' | 'color' | 'icon'>;

    /** null quando outra pessoa pagou */
    account_id: string | null;
    account?: Pick<Account, 'id' | 'name' | 'type'>;

    installment_id: string | null;
    installment_number: number | null;
    installment?: InstallmentInfo | null;

    recurring_id: string | null;
    recurring?: {
        id: string;
        frequency: RecurringFrequency;
        end_date: string | null;
        /** Débito automático */
        auto_pay?: boolean;
    } | null;

    /** true quando a data já chegou e o valor entrou no saldo da conta. */
    balance_applied?: boolean;
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
    /** Primeira parcela a lançar (ex.: 15 num parcelamento já na 15/24). */
    installment_start: number;
    /** O valor digitado é o total ou o de cada parcela. */
    amount_mode: 'total' | 'installment';
    /** Edição de parcela: repetir o valor nas parcelas seguintes. */
    apply_to_following: boolean;
    /** Divisão com contatos (null = sem divisão). */
    split: SplitForm | null;
    /** Débito automático (parcelado/recorrente). */
    auto_pay: boolean;
    is_recurring: boolean;
    frequency: RecurringFrequency;
    /** Tags livres (nomes). */
    tags: string[];
}

export type TransactionKind = 'split' | 'installment' | 'recurring' | 'shared';

export interface TransactionFilters {
    account_id?: string;
    category_id?: string;
    tag_id?: string;
    type?: TransactionType;
    /** YYYY-MM (padrão: mês atual) */
    month?: string;
    /** '1' = todo o período */
    all?: string;
    search?: string;
    kind?: TransactionKind;
    status?: 'paid' | 'pending' | 'overdue';
}

/** Totais do mês exibido na lista de transações. */
export interface TransactionsSummary {
    income: number;
    expense: number;
    balance: number;
    /** Despesas com data futura dentro do mês (agendadas). */
    due: number;
    due_count: number;
    /** Despesas vencidas e não pagas. */
    overdue: number;
    overdue_count: number;
    count: number;
}
