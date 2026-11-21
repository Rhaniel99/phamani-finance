import { router } from '@inertiajs/react';
import { Check, Hash, Pencil, Trash2, X } from 'lucide-react';
import { useState } from 'react';
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog';
import { tagSlug, useTags } from '@/hooks/use-tags';
import { destroy, update } from '@/routes/tags';
import type { Tag } from '@/types/phamani';

interface TagsModalProps {
    open: boolean;
    onOpenChange: (open: boolean) => void;
}

/**
 * Gerenciar tags: renomear (se o nome já existir, as duas viram uma só) e apagar.
 * Criar é direto no formulário da transação.
 */
export function TagsModal({ open, onOpenChange }: TagsModalProps) {
    const tags = useTags();

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent
                onOpenAutoFocus={(e) => e.preventDefault()}
                className="max-w-md overflow-hidden border-[#E8DCC4] bg-[#F5EFE6] p-0"
            >
                <DialogHeader className="border-b border-[#E8DCC4] px-6 pt-6 pb-4">
                    <DialogTitle className="text-xl text-[#3D2817]">
                        Tags
                    </DialogTitle>
                    <DialogDescription className="mt-1 text-sm text-[#8B7355]">
                        Crie tags direto na transação. Aqui você renomeia, junta
                        (renomeando para um nome que já existe) ou apaga.
                    </DialogDescription>
                </DialogHeader>

                <div className="max-h-[60vh] space-y-2 overflow-y-auto px-4 py-4">
                    {tags.length === 0 ? (
                        <p className="rounded-2xl border border-dashed border-[#D4C5A9] p-6 text-center text-sm text-[#8B7355]">
                            Nenhuma tag ainda.
                        </p>
                    ) : (
                        tags.map((tag) => (
                            <TagRow key={tag.id} tag={tag} all={tags} />
                        ))
                    )}
                </div>
            </DialogContent>
        </Dialog>
    );
}

function TagRow({ tag, all }: { tag: Tag; all: Tag[] }) {
    const [editing, setEditing] = useState(false);
    const [confirming, setConfirming] = useState(false);
    const [name, setName] = useState(tag.name);

    const target = all.find(
        (t) => t.id !== tag.id && tagSlug(t.name) === tagSlug(name),
    );

    function save() {
        const trimmed = name.trim();
        if (!trimmed || trimmed === tag.name) {
            setEditing(false);
            setName(tag.name);
            return;
        }

        router.put(
            update.url(tag.id),
            { name: trimmed },
            {
                preserveScroll: true,
                preserveState: true,
                onSuccess: () => setEditing(false),
            },
        );
    }

    function remove() {
        router.delete(destroy.url(tag.id), {
            preserveScroll: true,
            preserveState: true,
        });
    }

    const count = tag.transactions_count ?? 0;

    return (
        <div className="rounded-2xl border border-[#E8DCC4] bg-white p-3">
            {editing ? (
                <div className="space-y-1">
                    <div className="flex items-center gap-2">
                        <input
                            value={name}
                            onChange={(e) => setName(e.target.value)}
                            onKeyDown={(e) => {
                                if (e.key === 'Enter') save();
                                if (e.key === 'Escape') {
                                    setEditing(false);
                                    setName(tag.name);
                                }
                            }}
                            maxLength={40}
                            autoFocus
                            aria-label="Novo nome da tag"
                            className="flex-1 rounded-lg border-2 border-[#E8DCC4] px-2 py-1 text-sm text-[#3D2817] focus:border-[#6B4E3D] focus:outline-none"
                        />
                        <button
                            type="button"
                            onClick={save}
                            aria-label="Salvar"
                            className="rounded-md p-1.5 text-[#1F5428] hover:bg-[#E3F1E6]"
                        >
                            <Check className="h-4 w-4" />
                        </button>
                        <button
                            type="button"
                            onClick={() => {
                                setEditing(false);
                                setName(tag.name);
                            }}
                            aria-label="Cancelar"
                            className="rounded-md p-1.5 text-[#8B7355] hover:bg-[#E8DCC4]"
                        >
                            <X className="h-4 w-4" />
                        </button>
                    </div>
                    {target && (
                        <p className="ml-1 text-xs text-[#8B7355]">
                            Já existe “{target.name}”: as duas tags vão virar
                            uma só.
                        </p>
                    )}
                </div>
            ) : (
                <div className="flex items-center justify-between gap-2">
                    <span className="flex min-w-0 items-center gap-2">
                        <Hash className="h-4 w-4 shrink-0 text-[#8B7355]" />
                        <span className="truncate text-sm font-semibold text-[#3D2817]">
                            {tag.name}
                        </span>
                        <span className="shrink-0 text-xs text-[#8B7355]">
                            {count} {count === 1 ? 'transação' : 'transações'}
                        </span>
                    </span>

                    {confirming ? (
                        <span className="flex shrink-0 items-center gap-1 text-xs">
                            <button
                                type="button"
                                onClick={remove}
                                className="rounded-md bg-[#A65D57] px-2 py-1 font-semibold text-white"
                            >
                                Apagar
                            </button>
                            <button
                                type="button"
                                onClick={() => setConfirming(false)}
                                className="rounded-md px-2 py-1 text-[#8B7355] hover:bg-[#E8DCC4]"
                            >
                                Não
                            </button>
                        </span>
                    ) : (
                        <span className="flex shrink-0 items-center">
                            <button
                                type="button"
                                onClick={() => setEditing(true)}
                                aria-label={`Renomear ${tag.name}`}
                                className="rounded-md p-1.5 text-[#8B7355] hover:bg-[#E8DCC4] hover:text-[#3D2817]"
                            >
                                <Pencil className="h-3.5 w-3.5" />
                            </button>
                            <button
                                type="button"
                                onClick={() => setConfirming(true)}
                                aria-label={`Apagar ${tag.name}`}
                                className="rounded-md p-1.5 text-[#8B7355] hover:bg-[#FCE7E7] hover:text-[#A65D57]"
                            >
                                <Trash2 className="h-3.5 w-3.5" />
                            </button>
                        </span>
                    )}
                </div>
            )}
        </div>
    );
}
