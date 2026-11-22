export interface Contact {
    id: string;
    name: string;
    /** Contato vinculado a um usuário do Phamani (convite aceito). */
    linked_user_id: string | null;
    linked_user?: {
        id: string;
        name: string;
        email: string;
        avatar: string | null;
    } | null;
    /** E-mail do convite ainda não respondido. */
    pending_invite_email?: string | null;
    /** Cobrar essa pessoa no acerto do mês. */
    track_debts?: boolean;
}

export type SplitMode = 'equal' | 'custom';

export interface SplitParticipantForm {
    /** null = você */
    contact_id: string | null;
    /** Só no modo "valores" */
    amount: number | '';
}

export interface SplitForm {
    mode: SplitMode;
    participants: SplitParticipantForm[];
    /** null = você pagou */
    paid_by_contact_id: string | null;
    /**
     * false = compra para outra pessoa: você pagou, sua parte é zero e o valor fica "a receber".
     * Ausente = true.
     */
    include_me?: boolean;
    /**
     * Cobrar as partes no acerto (só de quem tem "cobrar" ligado nos Contatos). Ausente = true.
     */
    track?: boolean;
}

export interface TransactionSplit {
    id: string;
    contact_id: string | null;
    amount: string | number;
    contact?: Pick<Contact, 'id' | 'name'> | null;
    /** Compra para outra pessoa: quando ela devolveu (null = ainda a receber). */
    reimbursed_at?: string | null;
    reimbursement_account_id?: string | null;
    reimbursed_amount?: string | number | null;
    reimbursement_account?: { id: string; name: string } | null;
    /** Entra no acerto de quem pagou. */
    tracked?: boolean;
    settlement_id?: string | null;
    /** Pagamento informado por quem deve (pending) ou já confirmado. */
    settlement?: { id: string; status: SettlementStatus } | null;
}

export type SettlementStatus = 'pending' | 'confirmed' | 'rejected';

export type ShareStatus =
    | 'pending'
    | 'accepted'
    | 'declined'
    | 'left'
    | 'removed';

/** Origem de uma cópia (transação de outra pessoa dividida com você). */
export interface MirrorSource {
    id: string;
    user_id: string;
    account_id?: string | null;
    /** Só o tipo: diz se a original está num cartão (status "na fatura"). */
    account?: { id: string; name?: string; type: string } | null;
    date?: string;
    invoice_id?: string | null;
    invoice?: { id: string; due_date: string; paid_at?: string | null } | null;
    total_amount: string | number | null;
    paid_by_contact_id: string | null;
    user?: { id: string; name: string; avatar?: string | null } | null;
    paid_by?: Pick<Contact, 'id' | 'name' | 'linked_user_id'> | null;
    splits?: Array<{
        id: string;
        contact_id: string | null;
        amount: string | number;
        tracked?: boolean;
        reimbursed_at?: string | null;
        settlement_id?: string | null;
        settlement?: { id: string; status: SettlementStatus } | null;
        contact?: Pick<Contact, 'id' | 'name' | 'linked_user_id'> | null;
    }>;
}

export interface ShareLinkInfo {
    id: string;
    share?: {
        id: string;
        status: ShareStatus;
        owner_contact_id: string;
    } | null;
}

export interface PendingInvitation {
    id: string;
    created_at: string | null;
    inviter: {
        id: string;
        name: string;
        email: string;
        avatar: string | null;
    } | null;
}

export interface ShareSummary {
    id: string;
    status: ShareStatus;
    source_type: 'transaction' | 'installment' | 'recurring';
    owner: { id: string; name: string; avatar: string | null };
    name: string | null;
    date: string | null;
    total: number | null;
    my_amount: number;
    paid_by: string | null;
    you_paid: boolean;
    items: number;
    category_id: string | null;
    account_id: string | null;
}

export interface AppNotification {
    id: string;
    read_at: string | null;
    created_at: string;
    data: { kind: string; title: string; body: string; url: string | null };
}

export interface NotificationsProp {
    unread: number;
    pending: number;
    latest: AppNotification[];
}

export const SHARE_STATUS_LABELS: Record<ShareStatus, string> = {
    pending: 'aguardando',
    accepted: 'aceitou',
    declined: 'recusou',
    left: 'saiu',
    removed: 'removida',
};
