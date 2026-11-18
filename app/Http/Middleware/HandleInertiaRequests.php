<?php

namespace App\Http\Middleware;

use App\Enums\Category\Color;
use App\Enums\Category\Icon;
use App\Enums\EnumOptions;
use App\Enums\RecurringFrequency;
use Illuminate\Http\Request;
use Inertia\Middleware;

class HandleInertiaRequests extends Middleware
{
    /**
     * @var string
     */
    protected $rootView = 'app';

    public function version(Request $request): ?string
    {
        return parent::version($request);
    }

    /**
     * @return array<string, mixed>
     */
    public function share(Request $request): array
    {
        $user = $request->user();

        return [
            ...parent::share($request),
            'name' => config('app.name'),
            'auth' => [
                'user' => $user ? [
                    'id' => $user->id,
                    'name' => $user->name,
                    'email' => $user->email,
                    'avatar' => $user->avatar,
                ] : null,
            ],
            // Listas de enums usadas pelos formulários (antes eram compartilhadas pelo provider do módulo).
            'enums' => fn () => $user ? [
                'recurringFrequencies' => EnumOptions::from(RecurringFrequency::class),
                'categoryIcons' => EnumOptions::from(Icon::class),
                'categoryColors' => EnumOptions::from(Color::class, fn (Color $c) => ['hex' => $c->hex()]),
            ] : null,
        ];
    }
}
