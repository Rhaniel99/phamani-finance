<?php

namespace App\DTOs\Sharing;

use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\Rule;
use Spatie\LaravelData\Data;

class AcceptShareData extends Data
{
    public function __construct(
        /** Categoria no SEU sistema. */
        public string $category_id,

        /** Conta/cartão de onde sai o dinheiro quando VOCÊ é quem paga (opcional). */
        public ?string $account_id = null,
    ) {}

    /**
     * @return array<string, array<int, mixed>>
     */
    public static function rules(): array
    {
        return [
            'category_id' => ['required', 'uuid', Rule::exists('categories', 'id')->where('user_id', Auth::id())],
            'account_id' => ['nullable', 'uuid', Rule::exists('accounts', 'id')->where('user_id', Auth::id())],
        ];
    }
}
