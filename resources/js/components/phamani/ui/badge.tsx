import type { ButtonHTMLAttributes } from 'react';
import { cn } from '@/lib/utils';

interface BadgeProps extends ButtonHTMLAttributes<HTMLButtonElement> {
    variant?: 'default' | 'success' | 'warning' | 'danger' | 'outline';
}

const variants = {
    default: 'bg-[#3D2817] text-[#F5EFE6]',
    success: 'bg-[#E3F9E5] text-[#1F5428]',
    warning: 'bg-[#FFF4E5] text-[#663C00]',
    danger: 'bg-[#FCE7E7] text-[#D4183D]',
    outline: 'border-2 border-[#6B4F3A] text-[#6B4F3A]',
};

export function Badge({
    className,
    variant = 'default',
    type = 'button',
    ...props
}: BadgeProps) {
    return (
        <button
            type={type}
            className={cn(
                'inline-flex items-center rounded-full px-3 py-1 text-xs font-bold tracking-wider uppercase transition-colors focus:ring-2 focus:ring-[#6B4F3A] focus:ring-offset-2 focus:outline-none',
                variants[variant],
                className,
            )}
            {...props}
        />
    );
}
