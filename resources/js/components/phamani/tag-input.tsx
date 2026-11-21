import { Hash, X } from 'lucide-react';
import { useMemo, useRef, useState } from 'react';
import type { KeyboardEvent } from 'react';
import { tagSlug, useTags } from '@/hooks/use-tags';
import { cn } from '@/lib/utils';

const MAX_TAGS = 10;

interface TagInputProps {
    value: string[];
    onChange: (tags: string[]) => void;
    error?: string;
}

/**
 * Tags livres: digite e Enter (ou vírgula) vira um chip; aparecem sugestões das tags
 * que você já usa. "ifood" e "iFood" são a mesma tag (usa o nome já existente).
 */
export function TagInput({ value, onChange, error }: TagInputProps) {
    const existing = useTags();
    const [text, setText] = useState('');
    const [focused, setFocused] = useState(false);
    const [highlight, setHighlight] = useState(0);
    const inputRef = useRef<HTMLInputElement>(null);

    const chosen = useMemo(() => new Set(value.map(tagSlug)), [value]);

    const suggestions = useMemo(() => {
        const q = tagSlug(text);
        return existing
            .filter((t) => !chosen.has(tagSlug(t.name)))
            .filter((t) => !q || tagSlug(t.name).includes(q))
            .slice(0, 6);
    }, [existing, chosen, text]);

    function add(raw: string) {
        const name = raw.replace(/\s+/g, ' ').trim().slice(0, 40);
        if (!name || value.length >= MAX_TAGS) return;

        const slug = tagSlug(name);
        if (chosen.has(slug)) {
            setText('');
            return;
        }

        // Já existe com outra grafia? Usa o nome que você já tem.
        const match = existing.find((t) => tagSlug(t.name) === slug);
        onChange([...value, match?.name ?? name]);
        setText('');
        setHighlight(0);
    }

    function remove(index: number) {
        onChange(value.filter((_, i) => i !== index));
    }

    function onKeyDown(e: KeyboardEvent<HTMLInputElement>) {
        const open = focused && suggestions.length > 0;

        if (e.key === 'Enter' || e.key === ',') {
            e.preventDefault();
            if (open && text && suggestions[highlight]) {
                add(suggestions[highlight].name);
            } else if (text) {
                add(text);
            } else if (open && suggestions[highlight] && e.key === 'Enter') {
                add(suggestions[highlight].name);
            }
        } else if (e.key === 'Backspace' && !text && value.length > 0) {
            remove(value.length - 1);
        } else if (e.key === 'ArrowDown' && open) {
            e.preventDefault();
            setHighlight((h) => (h + 1) % suggestions.length);
        } else if (e.key === 'ArrowUp' && open) {
            e.preventDefault();
            setHighlight(
                (h) => (h - 1 + suggestions.length) % suggestions.length,
            );
        } else if (e.key === 'Escape') {
            inputRef.current?.blur();
        }
    }

    return (
        <div className="relative">
            <div
                onClick={() => inputRef.current?.focus()}
                className={cn(
                    'flex min-h-12 w-full cursor-text flex-wrap items-center gap-1.5 rounded-xl border-2 bg-white px-3 py-2 transition-colors',
                    focused ? 'border-[#6B4E3D]' : 'border-[#E8DCC4]',
                )}
            >
                {value.map((tag, i) => (
                    <span
                        key={`${tag}-${i}`}
                        className="inline-flex items-center gap-1 rounded-full bg-[#E8DCC4] py-0.5 pr-1 pl-2.5 text-sm text-[#3D2817]"
                    >
                        {tag}
                        <button
                            type="button"
                            aria-label={`Remover ${tag}`}
                            onClick={(e) => {
                                e.stopPropagation();
                                remove(i);
                            }}
                            className="rounded-full p-0.5 text-[#8B7355] hover:bg-[#D4C5A9] hover:text-[#3D2817]"
                        >
                            <X className="h-3 w-3" />
                        </button>
                    </span>
                ))}
                {value.length < MAX_TAGS && (
                    <input
                        ref={inputRef}
                        value={text}
                        onChange={(e) => {
                            setText(e.target.value);
                            setHighlight(0);
                        }}
                        onKeyDown={onKeyDown}
                        onFocus={() => setFocused(true)}
                        // Atraso para o clique numa sugestão contar antes de fechar a lista.
                        onBlur={() => {
                            setTimeout(() => setFocused(false), 120);
                            if (text) add(text);
                        }}
                        placeholder={
                            value.length === 0
                                ? 'Ex.: iFood, Amazon, viagem… (opcional)'
                                : ''
                        }
                        aria-label="Adicionar tag"
                        className="min-w-[8rem] flex-1 bg-transparent py-1 text-sm text-[#3D2817] placeholder:text-[#B8A88A] focus:outline-none"
                    />
                )}
            </div>

            {focused && suggestions.length > 0 && (
                <ul
                    role="listbox"
                    className="absolute z-30 mt-1 w-full overflow-hidden rounded-xl border border-[#E8DCC4] bg-[#F5EFE6] py-1 shadow-xl"
                >
                    {suggestions.map((t, i) => (
                        <li
                            key={t.id}
                            role="option"
                            aria-selected={i === highlight}
                        >
                            <button
                                type="button"
                                onMouseDown={(e) => {
                                    e.preventDefault();
                                    add(t.name);
                                }}
                                onMouseEnter={() => setHighlight(i)}
                                className={cn(
                                    'flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-[#3D2817]',
                                    i === highlight && 'bg-[#E8DCC4]',
                                )}
                            >
                                <Hash className="h-3.5 w-3.5 text-[#8B7355]" />
                                {t.name}
                            </button>
                        </li>
                    ))}
                </ul>
            )}

            {error && (
                <p className="mt-1 ml-1 text-xs text-[#D4183D]">{error}</p>
            )}
        </div>
    );
}

/** Chips de tags (somente leitura) para listas e drawer. */
export function TagChips({
    tags,
    className,
}: {
    tags?: { id?: string; name: string }[];
    className?: string;
}) {
    if (!tags || tags.length === 0) return null;

    return (
        <span className={cn('inline-flex flex-wrap gap-1', className)}>
            {tags.map((t) => (
                <span
                    key={t.id ?? t.name}
                    className="inline-flex items-center gap-0.5 rounded-md border border-[#E8DCC4] bg-white px-1.5 py-0.5 text-[10px] font-medium text-[#6B4E3D]"
                >
                    <Hash className="h-2.5 w-2.5 opacity-60" />
                    {t.name}
                </span>
            ))}
        </span>
    );
}
