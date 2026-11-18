import { useForm } from '@inertiajs/react';
import { store } from '@/routes/categories';
import type { CreateCategory } from '@/types/phamani';

export function useCategoryForm(onSuccess?: () => void) {
    const form = useForm<CreateCategory>({
        name: '',
        type: 'expense',
        color: 'brown',
        icon: 'tag',
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
