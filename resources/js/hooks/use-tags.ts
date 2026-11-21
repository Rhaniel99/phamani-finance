import { usePage } from '@inertiajs/react';
import type { Tag } from '@/types/phamani';

/** Tags do usuário (prop compartilhada em todas as páginas). */
export function useTags(): Tag[] {
    return (usePage().props.tags as Tag[] | undefined) ?? [];
}

/** Mesma normalização do back-end: minúsculas, sem acento, espaços simples. */
export function tagSlug(name: string): string {
    return name
        .normalize('NFD')
        .replace(/[̀-ͯ]/g, '')
        .toLowerCase()
        .replace(/\s+/g, ' ')
        .trim();
}
