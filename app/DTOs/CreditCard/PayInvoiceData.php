<?php

namespace App\DTOs\CreditCard;

use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\Rule;
use Spatie\LaravelData\Data;

class PayInvoiceData extends Data
{
    public function __construct(
        /** Conta de onde sai o dinheiro (não pode ser outro cartão). */
        public string $account_id,

        public string $date,
    ) {}

    /**
     * @return array<string, array<int, mixed>>
     */
    public static function rules(): array
    {
        return [
            'account_id' => [
                'required', 'uuid',
                Rule::exists('accounts', 'id')->where('user_id', Auth::id())->whereNot('type', 'credit'),
            ],
            'date' => ['required', 'date', 'before_or_equal:today'],
        ];
    }
}
