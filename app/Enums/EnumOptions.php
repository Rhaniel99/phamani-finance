<?php

namespace App\Enums;

/**
 * Converte enums em listas `{ value, label }` para o frontend.
 */
final class EnumOptions
{
    /**
     * @param  class-string<\BackedEnum>  $enum
     * @return list<array<string, string>>
     */
    public static function from(string $enum, ?callable $extra = null): array
    {
        return array_map(
            fn (\BackedEnum $case) => [
                'value' => (string) $case->value,
                'label' => method_exists($case, 'label') ? $case->label() : (string) $case->value,
                ...($extra ? $extra($case) : []),
            ],
            $enum::cases(),
        );
    }
}
