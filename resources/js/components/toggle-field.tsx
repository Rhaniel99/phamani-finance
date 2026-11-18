import type { ReactNode } from 'react';

interface ToggleFieldProps {
    label: string;
    icon?: ReactNode;
    active: boolean;
    onToggle: () => void;
}

export function ToggleField({
    label,
    icon,
    active,
    onToggle,
}: ToggleFieldProps) {
    return (
        <div className="flex items-center justify-between rounded-xl border border-[#E8DCC4] bg-[#FBF7F1] p-3">
            <div className="flex items-center gap-3">
                {icon && (
                    <div className="rounded-lg bg-[#E8DCC4] p-2 text-[#6B4E3D]">
                        {icon}
                    </div>
                )}
                <span className="font-medium text-[#3D2817]">{label}</span>
            </div>

            <button
                type="button"
                role="switch"
                aria-checked={active}
                aria-label={label}
                onClick={onToggle}
                className={`h-7 w-12 rounded-full p-1 transition-colors ${active ? 'bg-[#6B4E3D]' : 'bg-[#D4C5A9]'}`}
            >
                <div
                    className={`h-5 w-5 rounded-full bg-white shadow-sm transition-transform ${active ? 'translate-x-5' : 'translate-x-0'}`}
                />
            </button>
        </div>
    );
}
