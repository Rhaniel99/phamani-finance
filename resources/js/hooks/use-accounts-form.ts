import { useForm } from '@inertiajs/react';
import { store, update } from '@/routes/accounts';
import type { Account, CreateAccount } from '@/types/phamani';

function initialData(account?: Account | null): CreateAccount {
    return {
        name: account?.name ?? '',
        type: (account?.type as CreateAccount['type']) ?? 'checking',
        credit_limit:
            account?.credit_limit != null ? Number(account.credit_limit) : '',
        closing_day: account?.closing_day ?? '',
        due_day: account?.due_day ?? '',
        payment_account_id: account?.payment_account_id ?? '',
    };
}

/**
 * Formulário de conta/cartão. Sem `account` cria; com `account` edita
 * (o tipo não muda na edição).
 */
export function useAccountsForm(
    onSuccess?: () => void,
    account?: Account | null,
) {
    const form = useForm<CreateAccount>(initialData(account));

    function submit() {
        form.transform((data) => ({
            ...data,
            payment_account_id: data.payment_account_id || null,
        }));

        form.submit(account ? update(account.id) : store(), {
            preserveScroll: true,
            preserveState: true,
            onSuccess: () => {
                if (!account) form.reset();
                onSuccess?.();
            },
        });
    }

    return { form, submit, isEditing: !!account };
}
