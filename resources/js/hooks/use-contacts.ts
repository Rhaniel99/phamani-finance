import { usePage } from '@inertiajs/react';
import type { Contact } from '@/types/phamani';

/** Contatos do usuário (prop compartilhada pelo HandleInertiaRequests). */
export function useContacts(): Contact[] {
    return (usePage().props.contacts as Contact[] | undefined) ?? [];
}

/** Foto do contato (quando vinculado a um usuário do Phamani). */
export function useContactAvatar(): (
    contactId: string | null | undefined,
) => string | null {
    const contacts = useContacts();

    return (contactId) =>
        contacts.find((c) => c.id === contactId)?.linked_user?.avatar ?? null;
}
