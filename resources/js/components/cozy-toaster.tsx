import { router, usePage } from '@inertiajs/react';
import { useEffect } from 'react';
import { Toaster, toast } from 'sonner';

/**
 * Toaster no tema do Phamani.
 * - Mensagens de sucesso/erro chegam via `Inertia::flash('toast', [...])` (evento `flash` do Inertia v3).
 * - Erros de validação são exibidos automaticamente.
 */
export function CozyToaster() {
    const { errors } = usePage().props;

    useEffect(() => {
        return router.on('flash', (event) => {
            const data = event.detail.flash.toast;

            if (data) {
                toast[data.type](data.message);
            }
        });
    }, []);

    useEffect(() => {
        Object.values(errors ?? {}).forEach((message) => {
            toast.error(message, { id: message });
        });
    }, [errors]);

    return (
        <Toaster
            position="bottom-right"
            gap={12}
            toastOptions={{
                className:
                    'font-sans shadow-lg rounded-xl border border-[#D4C5A9]',
                style: { background: '#F5EFE6', color: '#3D2817' },
                classNames: {
                    success: 'border-l-[6px] border-l-[#6B4E3D] bg-[#F5EFE6]',
                    error: 'border-l-[6px] border-l-[#A65D57] bg-[#FFF5F5] text-[#8B4543]',
                    info: 'border-l-[6px] border-l-[#8B7355] bg-[#F5EFE6]',
                    actionButton: 'bg-[#6B4E3D] text-white',
                },
            }}
            icons={{
                success: <SuccessIcon />,
                error: <ErrorIcon />,
            }}
        />
    );
}

function SuccessIcon() {
    return (
        <div className="mr-2 flex h-5 w-5 items-center justify-center rounded-full bg-[#6B4E3D]">
            <svg
                className="h-3 w-3 text-[#F5EFE6]"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
                strokeWidth="3"
            >
                <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    d="M5 13l4 4L19 7"
                />
            </svg>
        </div>
    );
}

function ErrorIcon() {
    return (
        <div className="mr-2 flex h-5 w-5 items-center justify-center rounded-full bg-[#A65D57]">
            <svg
                className="h-3 w-3 text-[#FFF5F5]"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
                strokeWidth="3"
            >
                <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    d="M6 18L18 6M6 6l12 12"
                />
            </svg>
        </div>
    );
}
