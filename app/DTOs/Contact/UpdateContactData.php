<?php

namespace App\DTOs\Contact;

use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\Rule;
use Spatie\LaravelData\Attributes\Validation\Max;
use Spatie\LaravelData\Data;

class UpdateContactData extends Data
{
    public function __construct(
        #[Max(100)]
        public string $name,
    ) {}

    /**
     * @return array<string, array<int, mixed>>
     */
    public static function rules(): array
    {
        return [
            'name' => [
                'required', 'string',
                Rule::unique('contacts', 'name')->where('user_id', Auth::id())->ignore(request()->route('contact')),
            ],
        ];
    }

    /**
     * @return array<string, string>
     */
    public static function messages(): array
    {
        return ['name.unique' => 'Você já tem um contato com esse nome.'];
    }
}
