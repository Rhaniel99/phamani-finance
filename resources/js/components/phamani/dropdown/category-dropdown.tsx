import { Pencil } from 'lucide-react';
import { useState } from 'react';
import { CategoryIcon } from '@/components/phamani/category-icon';
import { DropdownTrigger } from '@/components/phamani/dropdown/dropdown-trigger';
import {
    DropdownMenu,
    DropdownMenuContent,
    DropdownMenuItem,
    DropdownMenuSeparator,
    DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import type { Category } from '@/types/phamani';

interface CategoryDropdownProps {
    value: Category | null;
    categories: Category[];
    onChange: (category: Category) => void;
    onCreate: () => void;
    onEdit?: (category: Category) => void;
}

export function CategoryDropdown({
    value,
    categories,
    onChange,
    onCreate,
    onEdit,
}: CategoryDropdownProps) {
    const [open, setOpen] = useState(false);

    return (
        <DropdownMenu open={open} onOpenChange={setOpen}>
            <DropdownMenuTrigger asChild>
                <DropdownTrigger
                    icon={
                        value ? (
                            <CategoryIcon
                                category={value}
                                className="h-8 w-8 shrink-0"
                            />
                        ) : undefined
                    }
                    title={value ? value.name : 'Categoria'}
                    placeholder={!value}
                />
            </DropdownMenuTrigger>

            <DropdownMenuContent
                side="bottom"
                align="start"
                sideOffset={8}
                className="z-[9999] max-h-72 w-(--radix-dropdown-menu-trigger-width) min-w-56 overflow-y-auto rounded-xl border border-[#E8DCC4] bg-[#F5EFE6] shadow-xl"
            >
                {categories.map((cat) => (
                    <DropdownMenuItem
                        key={cat.id}
                        onSelect={() => onChange(cat)}
                        className="group flex cursor-pointer items-center gap-3"
                    >
                        <CategoryIcon category={cat} className="h-7 w-7" />
                        <span className="min-w-0 flex-1 truncate">
                            {cat.name}
                        </span>
                        {onEdit && (
                            <button
                                type="button"
                                aria-label={`Editar ${cat.name}`}
                                title="Editar"
                                onClick={(e) => {
                                    e.preventDefault();
                                    e.stopPropagation();
                                    setOpen(false);
                                    onEdit(cat);
                                }}
                                className="rounded-md p-1.5 text-[#8B7355] opacity-60 group-hover:opacity-100 hover:bg-[#E8DCC4] hover:text-[#3D2817]"
                            >
                                <Pencil className="h-3.5 w-3.5" />
                            </button>
                        )}
                    </DropdownMenuItem>
                ))}

                <DropdownMenuSeparator />

                <DropdownMenuItem
                    onSelect={onCreate}
                    className="cursor-pointer font-medium text-[#6B4E3D]"
                >
                    + Criar nova categoria
                </DropdownMenuItem>
            </DropdownMenuContent>
        </DropdownMenu>
    );
}
