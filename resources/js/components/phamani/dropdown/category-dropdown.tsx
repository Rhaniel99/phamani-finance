import { ChevronDown } from 'lucide-react';
import { CategoryIcon } from '@/components/phamani/category-icon';
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
}

export function CategoryDropdown({
    value,
    categories,
    onChange,
    onCreate,
}: CategoryDropdownProps) {
    return (
        <DropdownMenu>
            <DropdownMenuTrigger asChild>
                <button
                    type="button"
                    className="flex w-full items-center justify-between rounded-xl border-2 border-[#E8DCC4] bg-white px-4 py-3 transition-colors hover:border-[#6B4E3D]"
                >
                    {value ? (
                        <div className="flex min-w-0 items-center gap-3">
                            <CategoryIcon
                                category={value}
                                className="h-8 w-8 shrink-0"
                            />
                            <span className="truncate text-[#3D2817]">
                                {value.name}
                            </span>
                        </div>
                    ) : (
                        <span className="text-[#8B7355]">Categoria</span>
                    )}
                    <ChevronDown className="h-4 w-4 shrink-0 text-[#8B7355]" />
                </button>
            </DropdownMenuTrigger>

            <DropdownMenuContent
                side="bottom"
                align="start"
                sideOffset={8}
                className="z-[9999] max-h-72 w-(--radix-dropdown-menu-trigger-width) overflow-y-auto rounded-xl border border-[#E8DCC4] bg-[#F5EFE6] shadow-xl"
            >
                {categories.map((cat) => (
                    <DropdownMenuItem
                        key={cat.id}
                        onSelect={() => onChange(cat)}
                        className="flex cursor-pointer items-center gap-3"
                    >
                        <CategoryIcon category={cat} className="h-7 w-7" />
                        <span>{cat.name}</span>
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
