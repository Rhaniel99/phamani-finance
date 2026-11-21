<?php

namespace App\Http\Middleware;

use App\Enums\Category\Color;
use App\Enums\Category\Icon;
use App\Enums\EnumOptions;
use App\Enums\RecurringFrequency;
use App\Interfaces\Services\IContactService;
use App\Interfaces\Services\IInvitationService;
use App\Interfaces\Services\ITagService;
use App\Models\Share;
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
            // Contatos para a divisão de contas (usados no formulário de transação em várias páginas).
            'contacts' => fn () => $user ? app(IContactService::class)->listForUser((string) $user->id) : [],
            // Tags do usuário: sugestões no formulário, filtro da lista e "Gerenciar tags".
            'tags' => fn () => $user ? app(ITagService::class)->listForUser((string) $user->id) : [],
            // Sino do cabeçalho. Hoje atualizado por polling (usePoll); com Reverb, um listener do Echo
            // só precisa recarregar esta mesma prop.
            'notifications' => fn () => $user ? [
                'unread' => $user->unreadNotifications()->count(),
                'pending' => app(IInvitationService::class)->pendingFor($user)->count()
                    + Share::query()->where('recipient_user_id', $user->id)->where('status', 'pending')->count(),
                'latest' => $user->notifications()->latest()->limit(8)->get(['id', 'data', 'read_at', 'created_at']),
            ] : null,
            // Listas de enums usadas pelos formulários (antes eram compartilhadas pelo provider do módulo).
            'enums' => fn () => $user ? [
                'recurringFrequencies' => EnumOptions::from(RecurringFrequency::class),
                'categoryIcons' => EnumOptions::from(Icon::class),
                'categoryColors' => EnumOptions::from(Color::class, fn (Color $c) => ['hex' => $c->hex()]),
            ] : null,
        ];
    }
}
