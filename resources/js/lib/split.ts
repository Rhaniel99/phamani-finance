import type { SplitForm, Transaction } from '@/types/phamani';

/** Sua parte numa divisão (prévia no front; o back-end faz o cálculo final). */
export function myShare(amount: number, split: SplitForm | null): number {
    if (!split || !amount) return amount || 0;

    const contacts = split.participants.filter((p) => p.contact_id !== null);
    if (contacts.length === 0) return amount;

    if (split.mode === 'custom') {
        const me = split.participants.find((p) => p.contact_id === null);
        return Number(me?.amount || 0);
    }

    return Math.floor((amount / (contacts.length + 1)) * 100) / 100;
}

/** Monta o formulário de divisão a partir de uma transação já salva (edição). */
export function splitFromTransaction(t: Transaction): SplitForm | null {
    if (t.total_amount == null || !t.splits?.length) return null;

    const amounts = t.splits.map((s) => Number(s.amount));
    const equal = Math.max(...amounts) - Math.min(...amounts) <= 0.01;

    // Você sempre primeiro
    const ordered = [
        ...t.splits.filter((s) => s.contact_id === null),
        ...t.splits.filter((s) => s.contact_id !== null),
    ];

    return {
        mode: equal ? 'equal' : 'custom',
        participants: ordered.map((s) => ({
            contact_id: s.contact_id,
            amount: equal ? '' : Number(s.amount),
        })),
        paid_by_contact_id: t.paid_by_contact_id ?? null,
    };
}

/**
 * Parte de cada participante para um valor (prévia).
 * Mesma regra do back-end: partes iguais ou proporcionais aos valores, em centavos,
 * e o centavo que sobra fica com quem pagou.
 */
export function splitBreakdown(
    amount: number,
    split: SplitForm | null,
): Array<{ contact_id: string | null; amount: number }> {
    if (!split || !amount) return [];

    const participants = split.participants.some((p) => p.contact_id === null)
        ? split.participants
        : [
              { contact_id: null, amount: 0 as number | '' },
              ...split.participants,
          ];

    if (!participants.some((p) => p.contact_id !== null)) return [];

    const weights = participants.map((p) =>
        split.mode === 'custom' ? Math.round(Number(p.amount || 0) * 100) : 1,
    );
    const sumWeights = weights.reduce((a, b) => a + b, 0);
    const totalCents = Math.round(amount * 100);

    const cents = weights.map((w) =>
        sumWeights > 0 ? Math.floor((totalCents * w) / sumWeights) : 0,
    );
    const payerIndex = Math.max(
        0,
        participants.findIndex(
            (p) => p.contact_id === (split.paid_by_contact_id ?? null),
        ),
    );
    cents[payerIndex] += totalCents - cents.reduce((a, b) => a + b, 0);

    return participants.map((p, i) => ({
        contact_id: p.contact_id,
        amount: cents[i] / 100,
    }));
}
