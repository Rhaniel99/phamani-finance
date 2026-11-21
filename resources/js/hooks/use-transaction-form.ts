import { useForm } from '@inertiajs/react';
import { today } from '@/lib/format';
import { splitFromTransaction } from '@/lib/split';
import { store, update } from '@/routes/transactions';
import type { Transaction, TransactionFormData } from '@/types/phamani';

function initialData(
    transaction?: Transaction | null,
    defaultAccountId?: string,
): TransactionFormData {
    return {
        // Parcelas guardam o nome com "(n/total)"; a descrição é o nome limpo.
        description: transaction
            ? (transaction.description ?? transaction.name)
            : '',
        // Numa divisão o campo "valor" é o total; a sua parte é calculada.
        amount: transaction
            ? Number(transaction.total_amount ?? transaction.amount)
            : '',
        type: transaction?.type ?? 'expense',
        category_id: transaction?.category_id ?? '',
        account_id: transaction?.account_id ?? defaultAccountId ?? '',
        date: transaction ? transaction.date.slice(0, 10) : today(),

        is_installment: false,
        installments_count: 2,
        installment_start: 1,
        // Padrão: valor da parcela (o número que aparece no boleto/fatura).
        amount_mode: 'installment',
        apply_to_following: false,
        split: transaction ? splitFromTransaction(transaction) : null,
        auto_pay: false,
        is_recurring: false,
        frequency: 'monthly',
        tags: transaction?.tags?.map((t) => t.name) ?? [],
    };
}

/**
 * Formulário de transação. Sem `transaction` cria uma nova;
 * com `transaction` edita a existente.
 */
export function useTransactionForm(
    transaction?: Transaction | null,
    onSuccess?: () => void,
    defaultAccountId?: string,
) {
    const form = useForm<TransactionFormData>(
        initialData(transaction, defaultAccountId),
    );

    function submit() {
        // O redirect "back" do Laravel recarrega a página atual com KPIs, gráficos e listas atualizados.
        form.submit(transaction ? update(transaction.id) : store(), {
            preserveScroll: true,
            onSuccess: () => {
                form.reset();
                onSuccess?.();
            },
        });
    }

    return { form, submit, isEditing: !!transaction };
}
