import { ChevronDown } from 'lucide-react';
import { forwardRef } from 'react';
import type { ComponentPropsWithoutRef, ReactNode } from 'react';
import { cn } from '@/lib/utils';

interface DropdownTriggerProps extends ComponentPropsWithoutRef<'button'> {
    /** Ícone à esquerda (ou um espaço vazio do mesmo tamanho, sem seleção). */
    icon?: ReactNode;
    title: string;
    subtitle?: string;
    placeholder?: boolean;
}

/**
 * Gatilho dos seletores de categoria e conta: mesma altura com ou sem seleção,
 * para os dois campos lado a lado ficarem alinhados.
 */
export const DropdownTrigger = forwardRef<
    HTMLButtonElement,
    DropdownTriggerProps
>(function DropdownTrigger(
    { icon, title, subtitle, placeholder, className, ...props },
    ref,
) {
    return (
        <button
            ref={ref}
            type="button"
            className={cn(
                'flex h-14 w-full items-center justify-between gap-2 rounded-xl border-2 border-[#E8DCC4] bg-white px-3 transition-colors hover:border-[#6B4E3D]',
                className,
            )}
            {...props}
        >
            <span className="flex min-w-0 items-center gap-3">
                {icon ?? (
                    <span className="h-8 w-8 shrink-0 rounded-lg border-2 border-dashed border-[#E8DCC4]" />
                )}
                <span className="min-w-0 text-left">
                    <span
                        className={cn(
                            'block truncate text-sm leading-tight',
                            placeholder
                                ? 'text-[#8B7355]'
                                : 'font-medium text-[#3D2817]',
                        )}
                    >
                        {title}
                    </span>
                    {subtitle && (
                        <span className="block truncate text-[11px] leading-tight text-[#8B7355]">
                            {subtitle}
                        </span>
                    )}
                </span>
            </span>
            <ChevronDown className="h-4 w-4 shrink-0 text-[#8B7355]" />
        </button>
    );
});
