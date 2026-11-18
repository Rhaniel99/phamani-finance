<?php

namespace App\DTOs\Transaction;

use App\Enums\RecurringFrequency;
use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\Rule;
use Spatie\LaravelData\Attributes\Validation\Date;
use Spatie\LaravelData\Attributes\Validation\In;
use Spatie\LaravelData\Attributes\Validation\Max;
use Spatie\LaravelData\Attributes\Validation\Min;
use Spatie\LaravelData\Attributes\Validation\RequiredIf;
use Spatie\LaravelData\Data;

class StoreTransactionData extends Data
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

        public bool $is_installment = false,

        #[RequiredIf('is_installment', true), Min(2), Max(360)]
        public ?int $installments_count = null,

        public bool $is_recurring = false,

        #[RequiredIf('is_recurring', true)]
        public ?RecurringFrequency $frequency = null,
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
