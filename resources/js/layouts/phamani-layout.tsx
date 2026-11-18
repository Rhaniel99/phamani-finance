import type { ReactNode } from 'react';
import { CozyToaster } from '@/components/cozy-toaster';

export default function PhamaniLayout({ children }: { children: ReactNode }) {
    return (
        <div className="min-h-screen w-full bg-[#F5EFE6] font-sans text-[#3D2817]">
            {children}
            <CozyToaster />
        </div>
    );
}
