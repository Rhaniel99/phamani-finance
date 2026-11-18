import { useForm } from '@inertiajs/react';
import { store } from '@/routes/accounts';
import type { CreateAccount } from '@/types/phamani';

export function useAccountsForm(onSuccess?: () => void) {
    const form = useForm<CreateAccount>({
        name: '',
        type: 'checking',
    });

    function submit() {
        form.submit(store(), {
            preserveScroll: true,
            preserveState: true,
            onSuccess: () => {
                form.reset();
                onSuccess?.();
            },
        });
    }

    return { form, submit };
}
