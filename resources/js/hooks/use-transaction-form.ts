import { useForm } from '@inertiajs/react';
import { today } from '@/lib/format';
import { store, update } from '@/routes/transactions';
import type { Transaction, TransactionFormData } from '@/types/phamani';

function initialData(transaction?: Transaction | null): TransactionFormData {
    return {
        // Parcelas guardam o nome com "(n/total)"; a descrição é o nome limpo.
        description: transaction
            ? (transaction.description ?? transaction.name)
            : '',
        amount: transaction ? Number(transaction.amount) : '',
        type: transaction?.type ?? 'expense',
        category_id: transaction?.category_id ?? '',
        account_id: transaction?.account_id ?? '',
        date: transaction ? transaction.date.slice(0, 10) : today(),

        is_installment: false,
        installments_count: 2,
        is_recurring: false,
        frequency: 'monthly',
    };
}

/**
 * Formulário de transação. Sem `transaction` cria uma nova;
 * com `transaction` edita a existente.
 */
export function useTransactionForm(
    transaction?: Transaction | null,
    onSuccess?: () => void,
) {
    const form = useForm<TransactionFormData>(initialData(transaction));

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
