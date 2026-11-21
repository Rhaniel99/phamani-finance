<?php

namespace App\DTOs\Category;

use App\Enums\Category\Color;
use App\Enums\Category\Icon;
use App\Models\Category;
use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\Rule;
use Spatie\LaravelData\Attributes\Validation\In;
use Spatie\LaravelData\Attributes\Validation\Max;
use Spatie\LaravelData\Data;

/**
 * Edição de categoria: nome, tipo, ícone e cor. As transações continuam ligadas a ela.
 */
class UpdateCategoryData extends Data
{
    public function __construct(
        #[Max(100)]
        public string $name,

        #[In(['income', 'expense', 'both'])]
        public string $type,

        public Color $color,

        public Icon $icon,
    ) {}

    /**
     * @return array<string, array<int, mixed>>
     */
    public static function rules(): array
    {
        $category = request()->route('category');

        return [
            'name' => [
                'required', 'string', 'max:100',
                Rule::unique('categories', 'name')
                    ->where('user_id', Auth::id())
                    ->ignore($category instanceof Category ? $category->id : null),
            ],
        ];
    }
}
