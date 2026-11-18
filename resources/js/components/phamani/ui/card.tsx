import { motion } from 'motion/react';
import type { HTMLMotionProps } from 'motion/react';
import { forwardRef } from 'react';
import { cn } from '@/lib/utils';

interface CardProps extends HTMLMotionProps<'div'> {
    variant?: 'default' | 'interactive';
}

const variants = {
    default: 'bg-[#FBF7F1] shadow-[0_4px_20px_rgba(0,0,0,0.08)]',
    interactive:
        'bg-[#FBF7F1] shadow-[0_4px_20px_rgba(0,0,0,0.08)] hover:shadow-[0_12px_40px_rgba(0,0,0,0.12)] cursor-pointer',
};

export const Card = forwardRef<HTMLDivElement, CardProps>(
    ({ className, variant = 'default', ...props }, ref) => (
        <motion.div
            ref={ref}
            className={cn(
                'rounded-3xl border border-[#E8DCC4] p-6 transition-colors',
                variants[variant],
                className,
            )}
            whileHover={variant === 'interactive' ? { y: -6 } : undefined}
            transition={{ type: 'spring', stiffness: 400, damping: 25 }}
            {...props}
        />
    ),
);

Card.displayName = 'Card';
