<?php

namespace App\Http\Controllers;

use App\Interfaces\Services\IAccountService;
use App\Interfaces\Services\ICategoryService;
use App\Interfaces\Services\IInvitationService;
use App\Interfaces\Services\IShareService;
use App\Models\ContactInvitation;
use App\Models\User;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Inertia\Inertia;
use Inertia\Response;

/**
 * Pendências: convites de conexão e divisões compartilhadas com você.
 */
class InboxController extends Controller
{
    public function __construct(
        protected IInvitationService $invitations,
        protected IShareService $shares,
        protected ICategoryService $categories,
        protected IAccountService $accounts,
    ) {}

    public function index(Request $request): Response
    {
        /** @var User $user */
        $user = $request->user();

        return Inertia::render('inbox/index', [
            'invitations' => fn () => $this->invitations->pendingFor($user)
                ->map(fn (ContactInvitation $i) => [
                    'id' => $i->id,
                    'created_at' => $i->created_at?->toIso8601String(),
                    'inviter' => $i->inviter?->only(['id', 'name', 'email', 'avatar']),
                ])
                ->values(),
            'pendingShares' => fn () => $this->shares->pendingFor($user),
            'acceptedShares' => fn () => $this->shares->acceptedFor($user),
            'categories' => fn () => $this->categories->listForUser($user->id),
            'accounts' => fn () => $this->accounts->listForUser($user->id),
        ]);
    }

    public function markNotificationsRead(Request $request): RedirectResponse
    {
        /** @var User $user */
        $user = $request->user();

        $user->unreadNotifications()->update(['read_at' => now()]);

        return back();
    }
}
