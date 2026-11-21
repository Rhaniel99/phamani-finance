import { Form } from '@/components/form';
import { DrawerShell } from '@/components/phamani/drawer/drawer-shell';
import { Label } from '@/components/ui/label';
import { useCategoryForm } from '@/hooks/use-category-form';
import { useEnums } from '@/hooks/use-enums';
import { CATEGORY_ICON_MAP } from '@/lib/category/icons';
import { cn } from '@/lib/utils';
import type { Category, CategoryType } from '@/types/phamani';

interface CreateCategoryDrawerProps {
    isOpen: boolean;
    onClose: () => void;
    /** Quando informado, edita esta categoria. */
    category?: Category | null;
}

const TYPE_LABELS: Record<CategoryType, string> = {
    expense: 'Despesa',
    income: 'Receita',
    both: 'Ambos',
};

export function CreateCategoryDrawer({
    isOpen,
    onClose,
    category,
}: CreateCategoryDrawerProps) {
    return (
        <DrawerShell
            isOpen={isOpen}
            onClose={onClose}
            title={category ? 'Editar Categoria' : 'Nova Categoria'}
            side="left"
        >
            {/* key: formulário novo a cada abertura/categoria editada */}
            <CategoryForm
                key={category?.id ?? 'new'}
                onClose={onClose}
                category={category}
            />
        </DrawerShell>
    );
}

function CategoryForm({
    onClose,
    category,
}: {
    onClose: () => void;
    category?: Category | null;
}) {
    const { form, submit, isEditing } = useCategoryForm(onClose, category);
    const { categoryIcons, categoryColors } = useEnums();

    return (
        <Form
            onSubmit={submit}
            className="flex flex-1 flex-col overflow-y-auto"
        >
            <div className="flex-1 space-y-6 p-6">
                <div className="space-y-2">
                    <Label htmlFor="category-name" className="ml-1">
                        Nome
                    </Label>
                    <input
                        id="category-name"
                        placeholder="Ex: Supermercado"
                        value={form.data.name}
                        onChange={(e) => form.setData('name', e.target.value)}
                        className="w-full rounded-xl border-2 border-[#E8DCC4] bg-white px-4 py-3 transition-colors outline-none focus:border-[#3D2817]"
                    />
                    {form.errors.name && (
                        <p className="ml-1 text-xs text-[#D4183D]">
                            {form.errors.name}
                        </p>
                    )}
                </div>

                <div className="space-y-2">
                    <Label className="ml-1">Tipo</Label>
                    <div className="flex gap-2 rounded-xl bg-[#E8DCC4]/50 p-1">
                        {(Object.keys(TYPE_LABELS) as CategoryType[]).map(
                            (t) => (
                                <button
                                    type="button"
                                    key={t}
                                    onClick={() => form.setData('type', t)}
                                    className={cn(
                                        'flex-1 rounded-lg py-2 text-sm font-medium',
                                        form.data.type === t
                                            ? 'bg-white text-[#3D2817] shadow-sm'
                                            : 'text-[#6B4E3D]',
                                    )}
                                >
                                    {TYPE_LABELS[t]}
                                </button>
                            ),
                        )}
                    </div>
                </div>

                <div className="space-y-2">
                    <Label className="ml-1">Ícone</Label>
                    <div className="grid grid-cols-5 gap-3">
                        {categoryIcons.map((icon) => {
                            const Icon = CATEGORY_ICON_MAP[icon.value];

                            return (
                                <button
                                    type="button"
                                    key={icon.value}
                                    title={icon.label}
                                    aria-label={icon.label}
                                    onClick={() =>
                                        form.setData('icon', icon.value)
                                    }
                                    className={cn(
                                        'flex items-center justify-center rounded-xl border-2 p-3 transition-all',
                                        form.data.icon === icon.value
                                            ? 'border-[#3D2817] bg-white text-[#3D2817]'
                                            : 'border-transparent bg-white/50 text-[#8B7355] hover:border-[#E8DCC4]',
                                    )}
                                >
                                    {Icon && <Icon className="h-5 w-5" />}
                                </button>
                            );
                        })}
                    </div>
                </div>

                <div className="space-y-2">
                    <Label className="ml-1">Cor</Label>
                    <div className="flex flex-wrap gap-3">
                        {categoryColors.map((color) => (
                            <button
                                key={color.value}
                                type="button"
                                title={color.label}
                                aria-label={color.label}
                                onClick={() =>
                                    form.setData('color', color.value)
                                }
                                style={{ backgroundColor: color.hex }}
                                className={cn(
                                    'h-8 w-8 rounded-full border-2 transition-all',
                                    form.data.color === color.value
                                        ? 'scale-110 border-[#3D2817] shadow-md'
                                        : 'border-transparent opacity-70 hover:opacity-100',
                                )}
                            />
                        ))}
                    </div>
                </div>
            </div>

            <div className="border-t border-[#E8DCC4] bg-[#FBF7F1] p-6">
                <button
                    disabled={form.processing || !form.data.name}
                    type="submit"
                    className="w-full rounded-xl bg-[#3D2817] py-4 text-lg font-bold text-[#F5EFE6] shadow-lg transition-colors hover:bg-[#2A1B0F] disabled:cursor-not-allowed disabled:opacity-50"
                >
                    {isEditing ? 'Salvar alterações' : 'Criar categoria'}
                </button>
            </div>
        </Form>
    );
}
