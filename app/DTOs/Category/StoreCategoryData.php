<?php

namespace App\DTOs\Category;

use App\Enums\Category\Color;
use App\Enums\Category\Icon;
use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\Rule;
use Spatie\LaravelData\Attributes\Validation\In;
use Spatie\LaravelData\Attributes\Validation\Max;
use Spatie\LaravelData\Data;

class StoreCategoryData extends Data
{
    public function __construct(
        #[Max(100)]
        public string $name,

        #[In(['income', 'expense', 'both'])]
        public string $type,

        public Color $color,

        public Icon $icon,

        public ?string $parent_id = null,
    ) {}

    /**
     * Regras que dependem do usuário autenticado.
     *
     * @return array<string, array<int, mixed>>
     */
    public static function rules(): array
    {
        return [
            'name' => [
                'required', 'string', 'max:100',
                Rule::unique('categories', 'name')->where('user_id', Auth::id()),
            ],
            'parent_id' => [
                'nullable', 'uuid',
                Rule::exists('categories', 'id')->where('user_id', Auth::id()),
            ],
        ];
    }
}
