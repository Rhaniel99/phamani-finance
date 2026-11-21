import { useForm } from '@inertiajs/react';
import { store, update } from '@/routes/categories';
import type { Category, CreateCategory } from '@/types/phamani';

function initialData(category?: Category | null): CreateCategory {
    return {
        name: category?.name ?? '',
        type: category?.type ?? 'expense',
        color: category?.color ?? 'brown',
        icon: category?.icon ?? 'tag',
    };
}

/** Sem `category` cria; com `category` edita. */
export function useCategoryForm(
    onSuccess?: () => void,
    category?: Category | null,
) {
    const form = useForm<CreateCategory>(initialData(category));

    function submit() {
        form.submit(category ? update(category.id) : store(), {
            preserveScroll: true,
            preserveState: true,
            onSuccess: () => {
                if (!category) form.reset();
                onSuccess?.();
            },
        });
    }

    return { form, submit, isEditing: !!category };
}
