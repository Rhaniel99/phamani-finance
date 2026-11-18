import type { ReactNode } from 'react';

interface DashboardMainProps {
    left: ReactNode;
    right: ReactNode;
}

export function DashboardMain({ left, right }: DashboardMainProps) {
    return (
        <main className="grid grid-cols-1 gap-8 lg:grid-cols-12">
            <div className="space-y-8 lg:col-span-9">{left}</div>
            <div className="space-y-8 lg:col-span-3">{right}</div>
        </main>
    );
}
