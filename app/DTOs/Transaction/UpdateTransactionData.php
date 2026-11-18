<?php

namespace App\DTOs\Transaction;

use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\Rule;
use Spatie\LaravelData\Attributes\Validation\Date;
use Spatie\LaravelData\Attributes\Validation\In;
use Spatie\LaravelData\Attributes\Validation\Max;
use Spatie\LaravelData\Attributes\Validation\Min;
use Spatie\LaravelData\Data;

/**
 * Edição de uma única transação (ou de uma parcela isolada).
 * Parcelamento e recorrência não são alterados por aqui.
 */
class UpdateTransactionData extends Data
{
    public function __construct(
        #[Max(255)]
        public string $description,

        #[Min(0.01)]
        public float $amount,

        #[In(['income', 'expense'])]
        public string $type,

        public string $category_id,

        public string $account_id,

        #[Date]
        public string $date,
    ) {}

    /**
     * Conta e categoria precisam pertencer ao usuário autenticado.
     *
     * @return array<string, array<int, mixed>>
     */
    public static function rules(): array
    {
        return [
            'category_id' => [
                'required', 'uuid',
                Rule::exists('categories', 'id')->where('user_id', Auth::id()),
            ],
            'account_id' => [
                'required', 'uuid',
                Rule::exists('accounts', 'id')->where('user_id', Auth::id()),
            ],
        ];
    }
}
